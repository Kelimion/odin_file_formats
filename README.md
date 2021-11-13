# File Formats

[Odin](https://github.com/odin-lang/Odin) implementations of various file formats (WIP).

## ISO Base Media File Format (BMFF)

The base container format used for `MP4`, `HEIF`, `JPEG 2000`, and other formats.

Implemented from [ISO/IEC Standard 14496, Part 12](https://www.iso.org/standard/68960.html), fifth edition 2015-12-15 specification.

See also: [Library of Congress archivist's information about the format](https://www.loc.gov/preservation/digital/formats/fdd/fdd000079.shtml).

### Status
* `open`  opens a file and returns a handle.
* `close` closes the file and cleans up anything allocated on behalf of the user.
* `parse` parses the opened file.
* `print` prints the parse tree.
* Various convenience functions to convert things to Odin-native types.
* Initial test harness.

### TODO
* Add parse options, e.g. parse / don't parse the `mdat` box, etc.
* Add handlers for more box types.
* Add more box constraints, e.g. type `foo_` may appear only in `bar_`, zero or more times.
* Add a writer.

## Other file formats

TBD. Various compression algoritms and file formats are under construction in my compression repository.