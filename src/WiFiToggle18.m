#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "ControlCenterUIKitShim.h"

@class WiFiToggle18Module;

@interface WiFiToggle18ContentViewController : CCUIButtonModuleViewController
@property (nonatomic, weak) WiFiToggle18Module *module;
@end

@interface WiFiToggle18Module : NSObject <CCUIContentModule>
@property (nonatomic, strong) WiFiToggle18ContentViewController *moduleContentViewController;
- (void)refreshState;
- (BOOL)setWiFiEnabled:(BOOL)enabled;
@end

#pragma mark - Wi-Fi backend

static id WT18WiFiManager(void) {
    Class managerClass = NSClassFromString(@"SBWiFiManager");
    SEL sharedInstanceSEL = NSSelectorFromString(@"sharedInstance");

    if (!managerClass || ![(id)managerClass respondsToSelector:sharedInstanceSEL]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sharedInstanceSEL);
}

static BOOL WT18WiFiIsPowered(void) {
    id manager = WT18WiFiManager();
    if (!manager) {
        return NO;
    }

    SEL isPoweredSEL = NSSelectorFromString(@"isPowered");
    if ([manager respondsToSelector:isPoweredSEL]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(manager, isPoweredSEL);
    }

    // Fallback seen on recent SpringBoard builds.
    SEL wiFiEnabledSEL = NSSelectorFromString(@"wiFiEnabled");
    if ([manager respondsToSelector:wiFiEnabledSEL]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(manager, wiFiEnabledSEL);
    }

    return NO;
}

static BOOL WT18SetWiFiEnabled(BOOL enabled) {
    id manager = WT18WiFiManager();
    if (!manager) {
        return NO;
    }

    SEL setWiFiEnabledSEL = NSSelectorFromString(@"setWiFiEnabled:");
    if ([manager respondsToSelector:setWiFiEnabledSEL]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(manager, setWiFiEnabledSEL, enabled);
        return YES;
    }

    // Last-resort fallback if Apple renamed the higher-level setter.
    SEL setPoweredSEL = NSSelectorFromString(@"setPowered:");
    if ([manager respondsToSelector:setPoweredSEL]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(manager, setPoweredSEL, enabled);
        return YES;
    }

    return NO;
}

#pragma mark - Module

@implementation WiFiToggle18Module

- (instancetype)init {
    self = [super init];
    if (self) {
        _moduleContentViewController = [[WiFiToggle18ContentViewController alloc] init];
        _moduleContentViewController.module = self;
        [self refreshState];
    }
    return self;
}

- (UIViewController *)contentViewController {
    return self.moduleContentViewController;
}

- (void)refreshState {
    [self.moduleContentViewController setSelected:WT18WiFiIsPowered()];
}

- (BOOL)setWiFiEnabled:(BOOL)enabled {
    BOOL success = WT18SetWiFiEnabled(enabled);
    if (success) {
        // SBWiFiManager transitions asynchronously. Reflect the requested state
        // immediately; viewWillAppear refreshes from the real radio state later.
        [self.moduleContentViewController setSelected:enabled];
    }
    return success;
}

@end

#pragma mark - Button UI

@implementation WiFiToggle18ContentViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        UIImage *wifiGlyph = [UIImage systemImageNamed:@"wifi"];
        self.glyphImage = wifiGlyph;
        self.selectedGlyphImage = wifiGlyph;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.module refreshState];
}

- (void)buttonTapped:(id)sender forEvent:(id)event {
    BOOL newState = !WT18WiFiIsPowered();
    if (![self.module setWiFiEnabled:newState]) {
        [self.module refreshState];
    }
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

@end
