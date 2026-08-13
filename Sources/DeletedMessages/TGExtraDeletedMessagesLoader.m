#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

typedef void (*TGExtraVoidMessage)(id receiver, SEL selector);
typedef void (*TGExtraObjectMessage)(id receiver, SEL selector, id object);

static BOOL TGExtraInvokeDeletedMessagesSetup(void) {
	Class cls = NSClassFromString(@"TGExtraDeletedMessages");
	SEL selector = NSSelectorFromString(@"setup");

	if (!cls || ![(id)cls respondsToSelector:selector]) {
		return NO;
	}

	((TGExtraVoidMessage)objc_msgSend)((id)cls, selector);
	return YES;
}

static void TGExtraScheduleDeletedMessagesSetup(NSUInteger attempt) {
	if (attempt > 20) {
		NSLog(@"[TGExtra] Deleted-message loader could not find its Swift entry point");
		return;
	}

	dispatch_after(
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
		dispatch_get_main_queue(),
		^{
			if (!TGExtraInvokeDeletedMessagesSetup()) {
				TGExtraScheduleDeletedMessagesSetup(attempt + 1);
			}
		}
	);
}

/// Called by TGExtra's existing settings controller after the switch changes.
void TGExtraSetDeletedMessagesEnabled(BOOL enabled) {
	dispatch_async(dispatch_get_main_queue(), ^{
		Class cls = NSClassFromString(@"TGExtraDeletedMessages");
		SEL selector = NSSelectorFromString(@"setEnabled:");
		if (!cls || ![(id)cls respondsToSelector:selector]) {
			return;
		}

		((TGExtraObjectMessage)objc_msgSend)((id)cls, selector, @(enabled));
	});
}

@interface TGExtraDeletedMessagesLoader : NSObject
@end

@implementation TGExtraDeletedMessagesLoader

+ (void)load {
	TGExtraScheduleDeletedMessagesSetup(0);
}

@end
