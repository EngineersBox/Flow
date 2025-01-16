# TODO

## Fix

* [X] Deleting a character causes PieceTable to segfault, most likely from a bad cursor position
* [X] Inserting a newline doesn't cause line to split
* [X] Newlines not being written to file when saving
* [X] Cursor offset is not correctly calculated after altering buffer contents. I.e inserting a newline into the middle of a line
* [ ] Backspace at start of line seems to fail sometimes and join only part of the line

## Implement

* [X] Mode system with `NORMAL`, `INSERT`, `VISUAL` and `COMMAND`
* [X] Piece table based buffer and window system
* [ ] Range based delete via visual mode
* [ ] Config loading
* [ ] Configurable colour scheme
* [ ] Configurable key maps
* [ ] Treesitter parsing for lines in buffer, using output to style line segments
* [ ] Cursor in insert mode should be a line instead of a block
* [ ] Cursor in insert mode should be able to hover over newline (whether it exists or not) to remove last character (before newline if exists)

## Refactor

* [ ] Improve `draw()` call structuring
