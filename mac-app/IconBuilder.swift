import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = CGFloat(Int(CommandLine.arguments[2]) ?? 1024)
let scale = CGFloat(Int(CommandLine.arguments[3]) ?? 1)
let pixelSize = Int(size * scale)

let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high
let bounds = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
NSColor.clear.setFill()
bounds.fill()

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x * CGFloat(pixelSize), y: y * CGFloat(pixelSize), width: width * CGFloat(pixelSize), height: height * CGFloat(pixelSize))
}

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowBlurRadius = 34 * scale
shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)

NSGraphicsContext.saveGraphicsState()
shadow.set()
let background = NSBezierPath(roundedRect: rect(0.05, 0.05, 0.90, 0.90), xRadius: 0.18 * CGFloat(pixelSize), yRadius: 0.18 * CGFloat(pixelSize))
NSColor.white.setFill()
background.fill()
NSGraphicsContext.restoreGraphicsState()

let innerShadow = NSShadow()
innerShadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
innerShadow.shadowBlurRadius = 10 * scale
innerShadow.shadowOffset = NSSize(width: 0, height: -5 * scale)

let navy = NSColor(red: 0.26, green: 0.33, blue: 0.43, alpha: 1)
let page = NSColor.white
let line = NSColor(red: 0.64, green: 0.68, blue: 0.74, alpha: 1)
let edge = NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)

let base = NSBezierPath()
base.move(to: NSPoint(x: 0.205 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.205 * CGFloat(pixelSize), y: 0.640 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.245 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.205 * CGFloat(pixelSize), y: 0.665 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.220 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.460 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.500 * CGFloat(pixelSize), y: 0.645 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.480 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.495 * CGFloat(pixelSize), y: 0.665 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.540 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.505 * CGFloat(pixelSize), y: 0.665 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.520 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.755 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.795 * CGFloat(pixelSize), y: 0.640 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.780 * CGFloat(pixelSize), y: 0.680 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.795 * CGFloat(pixelSize), y: 0.665 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.795 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.760 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.795 * CGFloat(pixelSize), y: 0.345 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.780 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.575 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.500 * CGFloat(pixelSize), y: 0.300 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.535 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.530 * CGFloat(pixelSize), y: 0.300 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.425 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.470 * CGFloat(pixelSize), y: 0.300 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.465 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)))
base.line(to: NSPoint(x: 0.240 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)))
base.curve(to: NSPoint(x: 0.205 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.220 * CGFloat(pixelSize), y: 0.330 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.205 * CGFloat(pixelSize), y: 0.345 * CGFloat(pixelSize)))
base.close()
navy.setFill()
base.fill()

func pagePath(left: Bool) -> NSBezierPath {
    let path = NSBezierPath()
    if left {
        path.move(to: NSPoint(x: 0.260 * CGFloat(pixelSize), y: 0.375 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.260 * CGFloat(pixelSize), y: 0.655 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.300 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.260 * CGFloat(pixelSize), y: 0.685 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.275 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.420 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.498 * CGFloat(pixelSize), y: 0.625 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.465 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.498 * CGFloat(pixelSize), y: 0.675 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.498 * CGFloat(pixelSize), y: 0.350 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.330 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.450 * CGFloat(pixelSize), y: 0.382 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.390 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)))
    } else {
        path.move(to: NSPoint(x: 0.502 * CGFloat(pixelSize), y: 0.350 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.502 * CGFloat(pixelSize), y: 0.625 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.580 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.502 * CGFloat(pixelSize), y: 0.675 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.535 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.700 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.740 * CGFloat(pixelSize), y: 0.655 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.725 * CGFloat(pixelSize), y: 0.700 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.740 * CGFloat(pixelSize), y: 0.685 * CGFloat(pixelSize)))
        path.line(to: NSPoint(x: 0.740 * CGFloat(pixelSize), y: 0.375 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.670 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.710 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.690 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)))
        path.curve(to: NSPoint(x: 0.502 * CGFloat(pixelSize), y: 0.350 * CGFloat(pixelSize)), controlPoint1: NSPoint(x: 0.610 * CGFloat(pixelSize), y: 0.365 * CGFloat(pixelSize)), controlPoint2: NSPoint(x: 0.550 * CGFloat(pixelSize), y: 0.382 * CGFloat(pixelSize)))
    }
    path.close()
    return path
}

NSGraphicsContext.saveGraphicsState()
innerShadow.set()
let leftPage = pagePath(left: true)
page.setFill()
leftPage.fill()
edge.setStroke()
leftPage.lineWidth = 1.2 * scale
leftPage.stroke()
let rightPage = pagePath(left: false)
page.setFill()
rightPage.fill()
edge.setStroke()
rightPage.lineWidth = 1.2 * scale
rightPage.stroke()
NSGraphicsContext.restoreGraphicsState()

let spine = NSBezierPath()
spine.move(to: NSPoint(x: 0.498 * CGFloat(pixelSize), y: 0.350 * CGFloat(pixelSize)))
spine.line(to: NSPoint(x: 0.502 * CGFloat(pixelSize), y: 0.625 * CGFloat(pixelSize)))
edge.setStroke()
spine.lineWidth = 2.0 * scale
spine.stroke()

func drawLine(x: CGFloat, y: CGFloat, width: CGFloat, angle: CGFloat = 0) {
    let center = NSPoint(x: x * CGFloat(pixelSize), y: y * CGFloat(pixelSize))
    let path = NSBezierPath(roundedRect: NSRect(x: center.x, y: center.y, width: width * CGFloat(pixelSize), height: 0.024 * CGFloat(pixelSize)), xRadius: 0.012 * CGFloat(pixelSize), yRadius: 0.012 * CGFloat(pixelSize))
    let origin = NSPoint(x: center.x + width * CGFloat(pixelSize) / 2, y: center.y + 0.012 * CGFloat(pixelSize))
    var moveToOrigin = AffineTransform(translationByX: -origin.x, byY: -origin.y)
    var rotate = AffineTransform()
    var moveBack = AffineTransform(translationByX: origin.x, byY: origin.y)
    rotate.rotate(byDegrees: angle)
    path.transform(using: moveToOrigin)
    path.transform(using: rotate)
    path.transform(using: moveBack)
    line.setFill()
    path.fill()
}

drawLine(x: 0.325, y: 0.585, width: 0.155, angle: -1)
drawLine(x: 0.325, y: 0.525, width: 0.155, angle: -2)
drawLine(x: 0.325, y: 0.465, width: 0.100, angle: -2)
drawLine(x: 0.555, y: 0.560, width: 0.155, angle: 2)
drawLine(x: 0.555, y: 0.500, width: 0.155, angle: 2)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

try png.write(to: outputURL)
