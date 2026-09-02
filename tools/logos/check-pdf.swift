#!/usr/bin/env swift
// Checks a brand mark PDF the way the app loads it: opens as a PDF, has
// exactly one page, and that page has a non-zero media box. Exits non-zero
// with a reason if not.
import CoreGraphics
import Foundation

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: check-pdf.swift <file.pdf>...\n".utf8))
    exit(2)
}

var failed = false
for path in paths {
    let url = URL(fileURLWithPath: path)
    func fail(_ reason: String) { print("FAIL \(path): \(reason)"); failed = true }

    guard let doc = CGPDFDocument(url as CFURL) else { fail("not a readable PDF"); continue }
    guard doc.numberOfPages == 1 else { fail("expected 1 page, found \(doc.numberOfPages)"); continue }
    guard let page = doc.page(at: 1) else { fail("page 1 missing"); continue }
    let box = page.getBoxRect(.mediaBox)
    guard box.width > 0, box.height > 0 else { fail("media box is empty (\(box.width)x\(box.height))"); continue }
    print("ok   \(path) — 1 page, \(Int(box.width))x\(Int(box.height))pt")
}
exit(failed ? 1 : 0)
