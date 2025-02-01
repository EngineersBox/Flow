# TODO

## Fix

* [X] Deleting a character causes PieceTable to segfault, most likely from a bad cursor position
* [X] Inserting a newline doesn't cause line to split
* [X] Newlines not being written to file when saving
* [X] Cursor offset is not correctly calculated after altering buffer contents. I.e inserting a newline into the middle of a line
* [X] Backspace at start of line seems to fail sometimes and join only part of the line
* [X] Cursor at end of document moving to the right causes a crash when there is no newline at the end
* [X] Buffer calculated in `buffer#reprocessRange` references original file content, it should use updated line content
* [ ] Hard to replicate issue where `shiftCursorRow` indexes window lines out of bounds. Implies `self.vx.screen.cursor_row` is not updated correctly in some operation beforehand, likely to with insert/delete at the end of the buffer
* [ ] `RwLock` synchronisation over `QueryHighlights` map is a naive solution that needs better management. Maybe a segmented distributed map?
* [ ] Modifiers don't change inserted character correctly
* [ ] TS queries after edit (i.e. remove `@` from `@import`) still return old highlight tag despite updating tree

## Implement

* [X] Mode system with `NORMAL`, `INSERT`, `VISUAL` and `COMMAND`
* [X] Piece table based buffer and window system
* [X] Cursor in insert mode should be a line instead of a block
* [X] Cursor in insert mode should be able to hover over newline (whether it exists or not) to remove last character (before newline if exists)
* [X] All operations (`insert`, `append`, `set` & `delete`) on `FileBuffer` need to update `buffer_line_range_indices` and `buffer_offset_range_indices`
* [X] Treesitter parsing for lines in buffer, using output to style line segments
* [X] Thread pool based rendering of each language highlight with main thread rendering un-highlighted text.
* [X] Config loading
* [X] Configurable colour scheme
* [X] Query tree sitter using language highlights SCM
* [ ] Range based delete via visual mode
* [ ] Configurable key maps

## Refactor

* [X] Optimise language loading to generate switch at compile time
* [X] Cache TS queries off heap (performed by a thread pool) and render cached results. Re-cache queries when tree changes.
* [X] Updated cached entries for only section of tree that changes
* [ ] Improve `draw()` call structuring
* [ ] Updates should be pushed to a thread pool via queues and `@atomicRmw` done on a single background thread
