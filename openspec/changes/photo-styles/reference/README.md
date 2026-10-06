# Style samples (task 0.1, round 1)

Rendered by `proto.swift`, a standalone macOS Core Image prototype of the recipes in design D1/D2/D4/D6.
Sample sheets are built by `sheet.py`.

    swiftc -O proto.swift -o proto && ./proto out <images...>   # MAXSIDE=4000 for full-res crops
    python3 sheet.py out

Sources: three Markepi demo photos (`tools/screenshots/src`: IMG_4334, k_IMG_6182, c_IMG_6970) and two CC0 Wikimedia Commons portraits:
"Outdoor portrait (Unsplash)" and "Portrait of elderly woman (Unsplash)".
