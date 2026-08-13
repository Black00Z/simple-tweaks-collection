import Foundation
import UIKit
import ObjectiveC

// Selectively adapted from Quadr-o's TGExtra PR #2. The storage, loader,
// capture flow, and overlay concept are retained; the runtime safety and
// caching behavior are implemented here for this Swiftgram/rootless build.

private var tgextraWrappedAlertActionKey: UInt8 = 0
private let tgextraDeletedOverlayTag = 0x74676578

private let tgextraDeleteKeywords = [
    "delete",
    "удал",
    "supprimer",
    "eliminar",
    "elimina",
    "löschen",
    "删除",
    "削除",
    "حذف",
    "xóa",
    "mesajı sil",
    "mesajlari sil",
    "mesajları sil"
]

private func tgextra_isDeleteAction(_ action: UIAlertAction) -> Bool {
    guard let title = action.title?.lowercased() else { return false }
    return tgextraDeleteKeywords.contains { title.contains($0) }
}

private func tgextra_keyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    return nil
}

private func tgextra_kvcValue(_ object: AnyObject?, key: String) -> AnyObject? {
    guard let object = object as? NSObject else { return nil }
    let selector = NSSelectorFromString(key)
    guard object.responds(to: selector) else { return nil }
    return object.value(forKey: key) as AnyObject?
}

private func tgextra_int32(_ object: AnyObject?) -> Int32? {
    (object as? NSNumber)?.int32Value
}

private func tgextra_int64(_ object: AnyObject?) -> Int64? {
    (object as? NSNumber)?.int64Value
}

private func tgextra_peerId(_ object: AnyObject?) -> Int64? {
    tgextra_int64(object) ?? tgextra_int64(tgextra_kvcValue(object, key: "id"))
}

private func tgextra_messageIdentifier(_ message: AnyObject) -> (messageId: Int32, peerId: Int64)? {
    let identifier = tgextra_kvcValue(message, key: "id")

    let messageId = tgextra_int32(tgextra_kvcValue(identifier, key: "id"))
        ?? tgextra_int32(identifier)
        ?? tgextra_int32(tgextra_kvcValue(message, key: "messageId"))

    let peerIdObject = tgextra_kvcValue(identifier, key: "peerId")
        ?? tgextra_kvcValue(message, key: "peerId")
    let peerId = tgextra_peerId(peerIdObject)

    guard let messageId = messageId, let peerId = peerId,
          messageId != 0, peerId != 0 else {
        return nil
    }
    return (messageId, peerId)
}

private func tgextra_messageObjects(_ value: AnyObject?) -> [AnyObject] {
    if let dictionary = value as? NSDictionary {
        return dictionary.allValues.compactMap { $0 as AnyObject? }
    }
    if let array = value as? NSArray {
        return array.compactMap { $0 as AnyObject? }
    }
    if let value = value {
        return [value]
    }
    return []
}

@objc(TGExtraDeletedMessages)
public final class TGExtraDeletedMessages: NSObject {
    @objc public static func setup() {
        DeletedMessageHook.shared.setEnabled(
            UserDefaults.standard.bool(forKey: kTGExtraShowDeletedMessages)
        )
    }

    /// Called by the existing TGExtra settings controller when the toggle changes.
    @objc public static func setEnabled(_ value: NSNumber) {
        let enabled = value.boolValue
        UserDefaults.standard.set(enabled, forKey: kTGExtraShowDeletedMessages)
        DeletedMessageHook.shared.setEnabled(enabled)
    }
}

public final class DeletedMessageHook: NSObject {
    public static let shared = DeletedMessageHook()

    private var alertControllerSwizzled = false
    private var messageCellLayoutSwizzled = false
    private var retryScheduled = false
    private var retryCount = 0
    private(set) var isEnabled = false

    private override init() {}

    public func setEnabled(_ enabled: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setEnabled(enabled)
            }
            return
        }

        isEnabled = enabled
        if enabled {
            install()
        }
    }

    public func install() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.install()
            }
            return
        }
        guard isEnabled else { return }

        if !alertControllerSwizzled {
            alertControllerSwizzled = swizzleAlertController()
        }

        if !messageCellLayoutSwizzled {
            messageCellLayoutSwizzled = swizzleMessageCellLayout()
        }

        if !alertControllerSwizzled || !messageCellLayoutSwizzled {
            scheduleRetry()
        } else {
            retryCount = 0
            print("[TGExtra] DeletedMessageHook installed")
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled, retryCount < 20, isEnabled else { return }
        retryScheduled = true
        retryCount += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.retryScheduled = false
            self.install()
        }
    }

    private func swizzleAlertController() -> Bool {
        guard let original = class_getInstanceMethod(
            UIAlertController.self,
            #selector(UIAlertController.viewWillAppear(_:))
        ), let swizzled = class_getInstanceMethod(
            UIAlertController.self,
            #selector(UIAlertController.tgextra_alertViewWillAppear(_:))
        ) else {
            print("[TGExtra] UIAlertController hook unavailable")
            return false
        }

        method_exchangeImplementations(original, swizzled)
        return true
    }

    private func swizzleMessageCellLayout() -> Bool {
        let classNames = [
            "ChatMessageItemView",
            "TelegramUI.ChatMessageItemView",
            "Swiftgram.ChatMessageItemView"
        ]
        let layoutSelector = #selector(UIView.layoutSubviews)
        let customSelector = #selector(UIView.tgextra_chatCell_layoutSubviews)

        guard let cellClass = classNames.lazy.compactMap({ NSClassFromString($0) }).first,
              let inheritedLayout = class_getInstanceMethod(cellClass, layoutSelector),
              let sourceCustomLayout = class_getInstanceMethod(UIView.self, customSelector) else {
            print("[TGExtra] ChatMessageItemView unavailable; deleted overlay will retry")
            return false
        }

        // If the target inherits layoutSubviews, give it its own method first.
        // This prevents exchanging UIView's method globally.
        _ = class_addMethod(
            cellClass,
            layoutSelector,
            method_getImplementation(inheritedLayout),
            method_getTypeEncoding(inheritedLayout)
        )

        guard let originalLayout = class_getInstanceMethod(cellClass, layoutSelector),
              class_addMethod(
                  cellClass,
                  customSelector,
                  method_getImplementation(sourceCustomLayout),
                  method_getTypeEncoding(sourceCustomLayout)
              ),
              let customLayout = class_getInstanceMethod(cellClass, customSelector) else {
            print("[TGExtra] Could not attach deleted overlay layout hook")
            return false
        }

        method_exchangeImplementations(originalLayout, customLayout)
        return true
    }
}

// MARK: - UIAlertController hook

extension UIAlertController {
    @objc func tgextra_alertViewWillAppear(_ animated: Bool) {
        // After the exchange this invokes Telegram/Swiftgram's original method.
        tgextra_alertViewWillAppear(animated)

        guard DeletedMessageHook.shared.isEnabled else { return }

        for action in actions where tgextra_isDeleteAction(action) {
            // viewWillAppear can run more than once for the same alert.
            guard objc_getAssociatedObject(action, &tgextraWrappedAlertActionKey) == nil,
                  let originalHandler = action.value(forKey: "handler") as? ((UIAlertAction) -> Void) else {
                continue
            }

            let wrappedHandler: (UIAlertAction) -> Void = { [weak self] action in
                self?.tgextra_captureFromWindow()
                originalHandler(action)
            }

            action.setValue(wrappedHandler, forKey: "handler")
            objc_setAssociatedObject(
                action,
                &tgextraWrappedAlertActionKey,
                true,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private func tgextra_captureFromWindow() {
        // ChatMessageItemView may be loaded only after the initial loader retry.
        DeletedMessageHook.shared.install()
        guard let window = tgextra_keyWindow(),
              let chatController = window.tgextra_findViewController(containing: "ChatControllerImpl") else {
            return
        }
        chatController.tgextra_saveSelectedMessages()
    }
}

// MARK: - Message capture

private extension UIWindow {
    func tgextra_findViewController(containing className: String) -> UIViewController? {
        rootViewController?.tgextra_findViewController(containing: className)
    }
}

private extension UIViewController {
    func tgextra_findViewController(containing className: String) -> UIViewController? {
        if NSStringFromClass(type(of: self)).contains(className) {
            return self
        }

        if let presented = presentedViewController,
           let found = presented.tgextra_findViewController(containing: className) {
            return found
        }

        for child in children {
            if let found = child.tgextra_findViewController(containing: className) {
                return found
            }
        }
        return nil
    }

    func tgextra_saveSelectedMessages() {
        let selected = tgextra_kvcValue(self, key: "selectedMessages")
        let selectedMessages = tgextra_messageObjects(selected)

        if !selectedMessages.isEmpty {
            selectedMessages.forEach { tgextra_persistMessage($0) }
        } else if let presented = tgextra_kvcValue(self, key: "presentedMessage") {
            tgextra_persistMessage(presented)
        }
    }

    func tgextra_persistMessage(_ message: AnyObject) {
        guard let identifier = tgextra_messageIdentifier(message) else { return }

        let text = tgextra_kvcValue(message, key: "text") as? String
        let timestamp = tgextra_int32(tgextra_kvcValue(message, key: "timestamp")) ?? 0

        var authorName: String?
        if let author = tgextra_kvcValue(message, key: "author") {
            let firstName = tgextra_kvcValue(author, key: "firstName") as? String
            let lastName = tgextra_kvcValue(author, key: "lastName") as? String
            let name = [firstName, lastName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            authorName = name.isEmpty ? nil : name
        }

        let entry = DeletedMessageEntry(
            messageId: identifier.messageId,
            peerId: identifier.peerId,
            text: text,
            authorName: authorName,
            timestamp: timestamp
        )
        DeletedMessageStore.shared.save(entry)
    }
}

// MARK: - Chat cell overlay

extension UIView {
    @objc func tgextra_chatCell_layoutSubviews() {
        // After the exchange this invokes the target cell's original layout.
        tgextra_chatCell_layoutSubviews()

        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.tgextra_updateDeletedOverlay()
            }
            return
        }
        tgextra_updateDeletedOverlay()
    }

    private func tgextra_updateDeletedOverlay() {
        guard DeletedMessageHook.shared.isEnabled else {
            tgextra_removeDeletedOverlay()
            return
        }

        let messageId = tgextra_int32(tgextra_kvcValue(self, key: "messageId"))
        let peerId = tgextra_peerId(tgextra_kvcValue(self, key: "peerId"))
        guard let messageId = messageId, let peerId = peerId,
              messageId != 0, peerId != 0 else {
            // Reused cells must not retain a previous message's indicator.
            tgextra_removeDeletedOverlay()
            return
        }

        if DeletedMessageStore.shared.contains(messageId: messageId, peerId: peerId) {
            tgextra_applyDeletedOverlay()
        } else {
            tgextra_removeDeletedOverlay()
        }
    }

    private func tgextra_applyDeletedOverlay() {
        let overlay: UIView
        if let existing = viewWithTag(tgextraDeletedOverlayTag) {
            overlay = existing
            overlay.frame = bounds
        } else {
            overlay = UIView(frame: bounds)
            overlay.tag = tgextraDeletedOverlayTag
            overlay.backgroundColor = UIColor.systemRed.withAlphaComponent(0.10)
            overlay.isUserInteractionEnabled = false
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            let badge = UILabel()
            badge.text = "Deleted"
            badge.font = .systemFont(ofSize: 10, weight: .semibold)
            badge.textColor = .secondaryLabel
            badge.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.sizeToFit()
            badge.frame = CGRect(
                x: max(4, bounds.width - badge.bounds.width - 10),
                y: 4,
                width: badge.bounds.width + 8,
                height: badge.bounds.height + 4
            )
            badge.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            overlay.addSubview(badge)
            addSubview(overlay)
        }

        overlay.frame = bounds
        bringSubviewToFront(overlay)
    }

    private func tgextra_removeDeletedOverlay() {
        viewWithTag(tgextraDeletedOverlayTag)?.removeFromSuperview()
    }
}
