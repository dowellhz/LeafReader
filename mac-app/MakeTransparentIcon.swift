import AppKit

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let inputImage = NSImage(contentsOf: inputURL),
      let inputCG = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fatalError("Failed to load input image")
}

let side = max(inputCG.width, inputCG.height)
let width = side
let height = side
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create bitmap context")
}

context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: width, height: height))
let originX = (width - inputCG.width) / 2
let originY = (height - inputCG.height) / 2
context.draw(inputCG, in: CGRect(x: originX, y: originY, width: inputCG.width, height: inputCG.height))

func offset(_ x: Int, _ y: Int) -> Int {
    y * bytesPerRow + x * bytesPerPixel
}

func isCheckerBackground(_ x: Int, _ y: Int) -> Bool {
    let i = offset(x, y)
    let r = Int(pixels[i])
    let g = Int(pixels[i + 1])
    let b = Int(pixels[i + 2])
    let a = Int(pixels[i + 3])
    if a == 0 { return true }

    let high = max(r, max(g, b))
    let low = min(r, min(g, b))
    let neutral = high - low <= 16
    guard neutral else { return false }

    let rawX = x - originX
    let rawY = y - originY
    guard rawX >= 0, rawX < inputCG.width, rawY >= 0, rawY < inputCG.height else {
        return true
    }

    // The supplied PNG has transparent areas flattened into a 30 px light
    // checkerboard. Only remove pixels that match that checker pattern; this
    // keeps the white PDF page opaque even where it touches the image edge.
    let squareSize = 30
    let isDarkSquare = ((rawX / squareSize) + (rawY / squareSize)).isMultiple(of: 2)
    if isDarkSquare {
        return low >= 232 && high <= 246
    }
    return low >= 248
}

var visited = [Bool](repeating: false, count: width * height)
var queue = [(Int, Int)]()

func enqueueIfBackground(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * width + x
    guard !visited[index], isCheckerBackground(x, y) else { return }
    visited[index] = true
    queue.append((x, y))
}

for x in 0..<width {
    enqueueIfBackground(x, 0)
    enqueueIfBackground(x, height - 1)
}
for y in 0..<height {
    enqueueIfBackground(0, y)
    enqueueIfBackground(width - 1, y)
}

var head = 0
while head < queue.count {
    let (x, y) = queue[head]
    head += 1
    enqueueIfBackground(x + 1, y)
    enqueueIfBackground(x - 1, y)
    enqueueIfBackground(x, y + 1)
    enqueueIfBackground(x, y - 1)
}

for y in 0..<height {
    for x in 0..<width where visited[y * width + x] {
        let i = offset(x, y)
        pixels[i] = 0
        pixels[i + 1] = 0
        pixels[i + 2] = 0
        pixels[i + 3] = 0
    }
}

guard let outputContext = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
), let outputCG = outputContext.makeImage() else {
    fatalError("Failed to create output image")
}

let rep = NSBitmapImageRep(cgImage: outputCG)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try png.write(to: outputURL)
