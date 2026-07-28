//	KCAnnotationShapeView.h
//
//	A stroke-only ring, drawn via a CAShapeLayer backing layer (chosen over overriding
//	-drawRect: since the whole point of this view is to have its layer's opacity animated
//	and then be torn down -- a shape layer needs no CG drawing pass at all, just a path).
//	Size and styling are read live from NSUserDefaults each time an instance is created
//	(default.annotationDiameter/StrokeWidth/StrokeColor/FillOpacity), not cached or passed
//	in by the caller, so there's nothing to configure via properties here.

#import <Cocoa/Cocoa.h>

@interface KCAnnotationShapeView : NSView

// Creates a view styled from the current default.annotation* NSUserDefaults values (read
// live at creation time), centered at `center` (in the coordinate space of whatever
// superview it will be added to).
- (instancetype)initWithCenter:(NSPoint)center;

@end
