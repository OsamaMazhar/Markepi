// Assembles Simulator.app's iPad Pro 13" (tablet5) chrome at 2x around a 2064x2752 screen.
// Outputs: frame.png (bezel + buttons, transparent screen hole) and mask.png (screen shape, white/alpha).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let C = "/Library/Developer/DeviceKit/Chrome/tablet5.devicechrome/Contents/Resources/"
let MASK = "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPad Pro 13-inch (M5).simdevicetype/Contents/Resources/75FF89F9-07DA-41E1-B66E-9AC4AF726865.pdf"
let out = CommandLine.arguments[1]
let s: CGFloat = 2                     // capture pixels per point
let screenW: CGFloat = 1032, screenH: CGFloat = 1376, bz: CGFloat = 46, pad: CGFloat = 20  // pad leaves room for buttons
let W = Int((screenW + 2*bz + 2*pad) * s), H = Int((screenH + 2*bz + 2*pad) * s)

func page(_ path: String) -> CGPDFPage { CGPDFDocument(URL(fileURLWithPath: path) as CFURL)!.page(at: 1)! }
func ctx() -> CGContext {
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high; return c
}
// Draw a PDF page stretched into rect r (points, origin top-left).
func draw(_ c: CGContext, _ name: String, _ r: CGRect, path: String? = nil) {
    let p = page(path ?? C + name + ".pdf"); let box = p.getBoxRect(.mediaBox)
    c.saveGState()
    let y = CGFloat(H) - (r.maxY * s)                       // flip to CG space
    c.translateBy(x: r.minX * s, y: y)
    c.scaleBy(x: r.width * s / box.width, y: r.height * s / box.height)
    c.clip(to: box); c.drawPDFPage(p); c.restoreGState()
}
func save(_ c: CGContext, _ file: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: file) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
}

// Device rect (points) = screen + bezel, inset by pad on the canvas.
let dx = pad, dy = pad, dw = screenW + 2*bz, dh = screenH + 2*bz, k: CGFloat = 96
let f = ctx()
// buttons first (they sit behind the body edge)
draw(f, "iPadPowerBTN", CGRect(x: dx + dw - 74 - 63, y: dy - 16 + 8, width: 63, height: 16))
draw(f, "VolBTN", CGRect(x: dx + dw - 8, y: dy + 100, width: 16, height: 52))
draw(f, "VolBTN", CGRect(x: dx + dw - 8, y: dy + 163, width: 16, height: 52))
// 9-slice body
draw(f, "iPadTL", CGRect(x: dx, y: dy, width: k, height: k))
draw(f, "iPadTR", CGRect(x: dx + dw - k, y: dy, width: k, height: k))
draw(f, "iPadBL", CGRect(x: dx, y: dy + dh - k, width: k, height: k))
draw(f, "iPadBR", CGRect(x: dx + dw - k, y: dy + dh - k, width: k, height: k))
draw(f, "iPadTop",   CGRect(x: dx + k, y: dy, width: dw - 2*k, height: k))
draw(f, "iPadBase",  CGRect(x: dx + k, y: dy + dh - k, width: dw - 2*k, height: k))
draw(f, "iPadLeft",  CGRect(x: dx, y: dy + k, width: k, height: dh - 2*k))
draw(f, "iPadRight", CGRect(x: dx + dw - k, y: dy + k, width: k, height: dh - 2*k))
save(f, out + "/chrome_raw.png")

// Screen mask at the screen rect.
let m = ctx()
draw(m, "", CGRect(x: dx + bz, y: dy + bz, width: screenW, height: screenH), path: MASK)
save(m, out + "/mask_raw.png")
print("canvas \(W)x\(H) screen at \(Int((dx+bz)*s)),\(Int((dy+bz)*s)) \(Int(screenW*s))x\(Int(screenH*s))")
