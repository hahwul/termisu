require "../../spec_helper"

# Records the byte stream while keeping Terminal's REAL cursor tracking.
# `CaptureTerminal` overrides `write` wholesale and therefore never runs
# `advance_cursor` — the very path under test — so these examples go through
# the backend instead.
private class RecordingBackend < Termisu::Terminal::Backend
  getter recorded = IO::Memory.new

  def write(data : String)
    @recorded << data
  end

  def write(data : Bytes)
    @recorded.write(data)
  end

  def flush
  end
end

private def full_frame(cols : Int32, rows : Int32, glyph : String)
  backend = RecordingBackend.new
  terminal = Termisu::Terminal.new(backend: backend, sync_updates: false)
  terminal.resize(cols, rows)
  rows.times { |y| cols.times { |x| terminal.set_cell(x, y, glyph) } }
  backend.recorded.clear
  terminal.sync
  backend.recorded.to_s
end

describe Termisu::Terminal do
  describe "cursor anchoring across an implicit wrap" do
    it "emits an absolute CUP for every row that runs to the last column" do
      # Where the cursor lands after the last column is the terminal's call (`am`
      # plus `xenl`), not ours. Without a CUP per row the whole frame rides on that
      # assumption, and one grapheme the terminal measures differently displaces
      # every row below it with nothing left to re-anchor them.
      stream = full_frame(10, 4, "a")

      # Each row NAMED, not just counted: four first-column moves would also be four
      # moves to the same row, which is the shape this is meant to rule out.
      4.times { |row| stream.should contain("\e[#{row + 1};1H") }
    end

    it "keeps the tracked position for a batch that stops short of the edge" do
      backend = RecordingBackend.new
      terminal = Termisu::Terminal.new(backend: backend, sync_updates: false)
      terminal.resize(10, 2)
      terminal.set_cell(0, 0, "a")
      terminal.sync
      backend.recorded.clear

      # Two batches, split by style, so the SECOND one starts exactly where writing
      # the first should have left the tracked cursor. The elision is still worth
      # having everywhere the implicit wrap is not involved, and an advance that
      # stopped tracking short writes would show up here as a third CUP.
      terminal.set_cell(0, 0, "b")
      terminal.set_cell(1, 0, "c", fg: Termisu::Color.red)
      terminal.render

      stream = backend.recorded.to_s
      stream.should contain("b")
      stream.should contain("c")
      # Exactly the two `render_transaction` emits around the frame: it renders under
      # an ephemeral cursor and restores the saved position afterwards.
      stream.scan(/\e\[\d+;\d+H/).size.should eq(2)
    end
  end
end
