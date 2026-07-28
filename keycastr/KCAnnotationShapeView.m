//	KCAnnotationShapeView.m

#if !__has_feature(objc_arc)
#error "ARC is required for this file -- enable with -fobjc-arc"
#endif

#import "KCAnnotationShapeView.h"
#import "NSUserDefaults+Utility.h"
#import <QuartzCore/QuartzCore.h>

@implementation KCAnnotationShapeView

- (instancetype)initWithCenter:(NSPoint)center
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    CGFloat diameter = [userDefaults floatForKey:@"default.annotationDiameter"];
    CGFloat strokeWidth = [userDefaults floatForKey:@"default.annotationStrokeWidth"];
    NSColor *strokeColor = [userDefaults colorForKey:@"default.annotationStrokeColor"];
    CGFloat fillOpacity = [userDefaults floatForKey:@"default.annotationFillOpacity"];

    NSRect frame = NSMakeRect(center.x - diameter / 2.0, center.y - diameter / 2.0, diameter, diameter);

    if (!(self = [super initWithFrame:frame])) {
        return nil;
    }

    // AppKit has no +layerClass hook (that's a UIKit/UIView thing) -- wantsLayer = YES on
    // its own always creates AppKit's own private NSViewBackingLayer. To host a specific
    // CALayer subclass, you assign it to `layer` yourself while it's still nil, then flip
    // wantsLayer; the setter only auto-creates a layer when one doesn't already exist.
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    self.layer = shapeLayer;
    self.wantsLayer = YES;

    // Inset by half the stroke width: CAShapeLayer centers a stroke on its path, so an
    // uninset full-bounds ellipse would get its outer half clipped by the view's own
    // bounds. Insetting keeps the ring's outer edge matching the configured diameter.
    CGRect bounds = NSRectToCGRect(NSMakeRect(0, 0, diameter, diameter));
    CGPathRef path = CGPathCreateWithEllipseInRect(CGRectInset(bounds, strokeWidth / 2.0, strokeWidth / 2.0), NULL);
    shapeLayer.path = path;
    CGPathRelease(path);

    shapeLayer.strokeColor = strokeColor.CGColor;
    shapeLayer.lineWidth = strokeWidth;
    // At fillOpacity 0.0 this is fully transparent (a pure outline); a small nonzero value
    // gives a faint tint of the same hue as the ring, without needing a separate fill color.
    shapeLayer.fillColor = [strokeColor colorWithAlphaComponent:fillOpacity].CGColor;

    return self;
}

@end
