#import <UIKit/UIKit.h>

@protocol CCUIContentModule <NSObject>
@property (nonatomic, readonly) UIViewController *contentViewController;
@end

@interface CCUIButtonModuleViewController : UIViewController
@property (nonatomic, retain) UIImage *glyphImage;
@property (nonatomic, retain) UIImage *selectedGlyphImage;
@property (nonatomic, retain) UIColor *glyphColor;
@property (nonatomic, retain) UIColor *selectedGlyphColor;
@property (getter=isSelected, nonatomic) BOOL selected;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *valueText;
- (void)buttonTapped:(id)sender forEvent:(id)event;
@end
