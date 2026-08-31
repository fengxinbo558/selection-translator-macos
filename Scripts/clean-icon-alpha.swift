import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("usage: clean-icon-alpha.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL

guard
    let source = CGImageSourceCreateWithURL(inputURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    fputs("unable to read or prepare icon image\n", stderr)
    exit(1)
}

let size = CGFloat(min(image.width, image.height))
let inset = size * 0.04
let radius = size * 0.16
let iconRect = CGRect(
    x: inset,
    y: inset,
    width: CGFloat(image.width) - inset * 2,
    height: CGFloat(image.height) - inset * 2
)

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.addPath(CGPath(
    roundedRect: iconRect,
    cornerWidth: radius,
    cornerHeight: radius,
    transform: nil
))
context.clip()
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

guard
    let cleanedImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("unable to create cleaned icon image\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, cleanedImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("unable to write cleaned icon image\n", stderr)
    exit(1)
}
