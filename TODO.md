# TODO

## Fix

* [ ] Deleting a character causes PieceTable to segfault, most likely from a bad cursor position

## Implement

* [X] Mode system with `NORMAL`, `INSERT`, `VISUAL` and `COMMAND`
* [X] Piece table based buffer and window system
* [ ] Range based delete via visual mode
* [ ] Config loading
* [ ] Configurable colour scheme
* [ ] Configurable key maps
* [ ] Treesitter parsing for lines in buffer, using output to style line segments

## Refactor

* [ ] Improve `draw()` call structuring
