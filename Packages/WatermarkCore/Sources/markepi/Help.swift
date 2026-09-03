// The `--help` screen. Kept in its own file so the flag table above stays readable.

let helpText = """
markepi — add text watermarks, logos, borders and date stamps to an image.
Runs the same WatermarkCore pipeline as the Markepi app: EXIF, GPS, HDR gain
map and colour profile are preserved unless --privacy says otherwise.

USAGE
  markepi <input-image> -o <output-image> [options]
  markepi --list-fonts

GENERAL
  -o, --output <path>          Destination file. Required.
  -f, --force                  Overwrite the output file if it already exists.
      --format <fmt>           preserve | heic | jpeg | png | tiff
                               (default: preserve — keeps the source format)
      --quality <0–1>          Quality for lossy formats (default: 1.0)
      --padding <points>       Minimum edge padding for watermark layers.
                               The engine uses max(padding, 4% of the short edge).
                               (default: 20)
      --privacy <profile>      preserveAll | stripSensitive | minimalPublic
                               stripSensitive drops GPS and serial numbers;
                               minimalPublic keeps only the essentials.
                               (default: preserveAll)
  -h, --help                   Show this help.
      --list-fonts             List the bundled fonts and exit.

TEXT WATERMARK                 (applied when --text is given)
      --text <string>          The watermark text. EXIF tokens are substituted:
                               {camera_model} {lens} {aperture} {focal_length}
                               {shutter_speed} {iso} {date} {gps} {dimensions}
                               {format}   — missing values render as "--".
      --text-position <pos>    topLeft | topCenter | topRight
                               middleLeft | center | middleRight
                               bottomLeft | bottomCenter | bottomRight
                               (default: bottomRight)
      --text-size <0.01–0.90>  Text height as a fraction of image height
                               (default: 0.045)
      --text-font <name>       A font id from --list-fonts, or any PostScript
                               name installed on this Mac
                               (default: Pacifico-Regular)
      --text-color <hex>       #RRGGBB or #RRGGBBAA (default: #FFFFFF)
      --text-opacity <0–1>     (default: 1.0)

LOGO WATERMARK                 (applied when --logo is given)
      --logo <path>            Logo image file. PNG keeps transparency.
      --logo-position <pos>    Same nine values as --text-position
                               (default: bottomRight)
      --logo-size <0.01–0.90>  Logo width as a fraction of image width
                               (default: 0.15)
      --logo-opacity <0–1>     (default: 1.0)
      --logo-rotation <deg>    Clockwise rotation in degrees (default: 0)

BORDER / WHITE FRAME           (applied when --border or any --border-* is given)
      --border                 Draw the white frame.
      --border-width <0.03–0.05>
                               Frame width as a fraction of the short edge
                               (default: 0.04)
      --border-caption <text>  Free text before the metadata fields, e.g.
                               "Shot on". EXIF tokens work here too.
      --border-fields <list>   Comma-separated metadata fields printed in the
                               bottom border, always in this canonical order:
                               cameraModel, lens, focalLength, aperture,
                               shutterSpeed, iso, date, dimensions, format, gps
                               (default: cameraModel,focalLength,aperture,
                                shutterSpeed,iso,dimensions,format)
      --border-no-text         Draw the frame with no caption at all.
      --border-text-color <hex>
                               Caption colour (default: black on a gallery
                               mat, #555555 on a classic one)
      --border-text-size <0.005–0.05>
                               Caption size as a fraction of the short edge
                               (default: 0.018, classic only)
      --border-style <style>   classic | gallery (default: gallery)

  Gallery style is measured in millimetres, converted at --border-dpi:
      --border-mm <0.5–50>     Mat thickness (default: 8)
      --border-caption-mm <0.5–20>
                               Caption text height (default: 5.84)
      --border-logo-mm <0.5–30>
                               Brand mark height (default: 13.6)
      --border-dpi <36–2400>   Resolution the millimetres convert against.
                               Omit to use the photo's own resolution when it
                               is a real print measurement, else 300.
      --border-keyline / --border-no-keyline
                               Black rule between photo and mat (default: on)
      --border-logo-variant <v>
                               color | monochrome (default: color)
      --border-left-primary <slot>, --border-left-secondary <slot>,
      --border-right-primary <slot>, --border-right-secondary <slot>
                               Caption slots: "field:<name>", "text:<literal>"
                               or "" for empty.

DATE STAMP                     (applied when --date-stamp or any --date-* is given)
      --date-stamp             Burn in the retro orange film-databack date,
                               read from the photo's capture date.
      --date-format <fmt>      dayMonthYear | dayMonthYearDash | yearMonthDay
                               monthDayYear | classicShortYear | dayMonthText
                               (default: dayMonthYear)
      --date-size <0.015–0.12> Digit height as a fraction of image height
                               (default: 0.035)
      --date-position <pos>    Same nine values as --text-position; film cameras
                               used the lower corners (default: bottomLeft)

LAYER ORDER
  Text is composited first, then the logo, then the border, then the date
  stamp. With a border on, watermarks are inset so they stay inside the frame.

EXAMPLES
  markepi photo.heic -o out.heic --text "© Osama Mazhar"
  markepi photo.jpg -o out.jpg --text "{camera_model} · {focal_length} · ISO {iso}" \\
      --text-position topLeft --text-size 0.03 --text-color "#FFFFFFCC"
  markepi photo.jpg -o out.jpg --border --border-caption "Shot on" \\
      --border-fields cameraModel,focalLength,iso
  markepi photo.jpg -o out.png --format png --logo logo.png --logo-size 0.2 \\
      --logo-opacity 0.6 --logo-position topRight
  markepi photo.jpg -o out.jpg --date-stamp --date-format classicShortYear
  markepi photo.jpg -o clean.jpg --text "©" --privacy stripSensitive

NOT COVERED
  Videos, Live Photos, signatures and C2PA Content Credentials stay in the app.
"""
