# To do

- Diagnose why Plupo sometimes misses the start of a file drag from the Dock's Downloads stack. Compare Finder and Dock with the same file and record when Plupo detects mouse movement, a drag pasteboard change, available drag data, and entry into the screen-edge drop zone. Keep filenames and file contents out of the diagnostic log.
- Investigate why dragged files sometimes end up with a generic name such as `Image.png`. Compare the original name, the shelf card title, and the filename after dropping into Finder. Check file URLs from Finder, browser images, and clipboard imports to identify where the name is lost.
