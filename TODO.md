# TODO

## Fix

* [X] Deleting a character causes PieceTable to segfault, most likely from a bad cursor position
* [X] Inserting a newline doesn't cause line to split
* [X] Newlines not being written to file when saving
* [X] Cursor offset is not correctly calculated after altering buffer contents. I.e inserting a newline into the middle of a line
* [X] Backspace at start of line seems to fail sometimes and join only part of the line
* [X] Cursor at end of document moving to the right causes a crash when there is no newline at the end
* [ ] Hard to replicate issue where `shiftCursorRow` indexes window lines out of bounds. Implies `self.vx.screen.cursor_row` is not updated correctly in some operation beforehand, likely to with insert/delete at the end of the buffer

## Implement

* [X] Mode system with `NORMAL`, `INSERT`, `VISUAL` and `COMMAND`
* [X] Piece table based buffer and window system
* [X] Cursor in insert mode should be a line instead of a block
* [X] Cursor in insert mode should be able to hover over newline (whether it exists or not) to remove last character (before newline if exists)
* [X] All operations (`insert`, `append`, `set` & `delete`) on `FileBuffer` need to update `buffer_line_range_indices` and `buffer_offset_range_indices`
* [X] Treesitter parsing for lines in buffer, using output to style line segments
* [ ] Range based delete via visual mode
* [ ] Config loading
* [ ] Configurable colour scheme
* [ ] Configurable key maps
* [ ] Query tree sitter using language highlights SCM
* [X] Thread pool based rendering of each language highlight with main thread rendering un-highlighted text.

## Refactor

* [X] Optimise language loading to generate switch at compile time
* [ ] Improve `draw()` call structuring
* [ ] Cache TS queries off heap (performed by a thread pool) and render cached results. Re-cache queries when tree changes.
* [ ] Updated cached entries for only section of tree that changes
