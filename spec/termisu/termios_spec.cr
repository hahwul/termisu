require "../spec_helper"

describe Termisu::Termios do
  describe "#enable_raw_mode" do
    it "raises IO::Error with invalid file descriptor" do
      termios = Termisu::Termios.new(-1)

      expect_raises(IO::Error, /tcgetattr.*failed/) do
        termios.enable_raw_mode
      end
    end
  end

  describe "#restore" do
    it "is safe to call before enable_raw_mode and multiple times" do
      termios = Termisu::Termios.new(1)
      # No state saved, so restore is a no-op
      termios.restore
      termios.restore
      termios.restore

      # Even with invalid FD, restore is safe when no state saved
      termios_invalid = Termisu::Termios.new(-1)
      termios_invalid.restore
    end
  end

  describe "state management" do
    it "handles enable_raw_mode -> restore lifecycle on TTY" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.enable_raw_mode
      termios.restore
    end
  end

  describe "#current_mode" do
    it "returns nil before any mode is set" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.current_mode.should be_nil
    end

    it "returns the mode after set_mode is called" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.raw)
      termios.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      termios.try &.restore
    end

    it "is reset to nil after restore" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.raw)
      termios.restore
      termios.current_mode.should be_nil
    end
  end

  describe "#set_mode" do
    it "raises IO::Error with invalid file descriptor" do
      termios = Termisu::Termios.new(-1)

      expect_raises(IO::Error, /tcgetattr.*failed/) do
        termios.set_mode(Termisu::Terminal::Mode.raw)
      end
    end

    it "sets raw mode" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.raw)
      termios.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      termios.try &.restore
    end

    it "sets cooked mode" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.cooked)
      termios.current_mode.should eq(Termisu::Terminal::Mode.cooked)
    ensure
      termios.try &.restore
    end

    it "sets cbreak mode" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.cbreak)
      termios.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
    ensure
      termios.try &.restore
    end

    it "sets password mode" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.password)
      termios.current_mode.should eq(Termisu::Terminal::Mode.password)
    ensure
      termios.try &.restore
    end

    it "sets semi_raw mode" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode.semi_raw)
      termios.current_mode.should eq(Termisu::Terminal::Mode.semi_raw)
    ensure
      termios.try &.restore
    end

    it "handles mode transitions" do
      termios = Termisu::Termios.new(STDOUT.fd)

      termios.set_mode(Termisu::Terminal::Mode.raw)
      termios.current_mode.should eq(Termisu::Terminal::Mode.raw)

      termios.set_mode(Termisu::Terminal::Mode.cooked)
      termios.current_mode.should eq(Termisu::Terminal::Mode.cooked)

      termios.set_mode(Termisu::Terminal::Mode.raw)
      termios.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      termios.try &.restore
    end

    it "sets custom mode combinations" do
      termios = Termisu::Termios.new(STDOUT.fd)
      custom = Termisu::Terminal::Mode::Echo | Termisu::Terminal::Mode::Canonical
      termios.set_mode(custom)
      termios.current_mode.should eq(custom)
    ensure
      termios.try &.restore
    end
  end

  describe "enable_raw_mode compatibility" do
    it "delegates to set_mode with raw preset" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.enable_raw_mode
      termios.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      termios.try &.restore
    end
  end

  # `apply_input_flags`/`apply_output_flags` take `LibC::Termios` — a STRUCT, so by value.
  # Every c_iflag/c_oflag change they made was written to a copy and discarded, leaving raw
  # mode with ICRNL, IXON and OPOST still on: a pasted CRLF arrived as two newlines and
  # Ctrl+S froze the application. Only c_lflag/c_cflag/c_cc, mutated inline in `set_mode`,
  # ever reached the terminal, so `Mode::CrToNl`, `Mode::FlowControl` and
  # `Mode::OutputProcessing` had no effect either.
  #
  # Assert against the FD, not the tracked mode — `current_mode` was right the whole time,
  # which is how every existing spec in this file passed against the broken code.
  describe "raw mode input/output flags" do
    it "clears CR→NL translation, flow control and output post-processing" do
      pending! "needs a real tty" unless STDOUT.tty?
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.enable_raw_mode

      tios = uninitialized LibC::Termios
      LibC.tcgetattr(STDOUT.fd, pointerof(tios)).should eq(0)
      (tios.c_iflag & LibC::ICRNL).should eq(0)
      (tios.c_iflag & LibC::IXON).should eq(0)
      (tios.c_oflag & LibC::OPOST).should eq(0)
    ensure
      termios.try &.restore
    end

    it "honours a mode that asks for CR→NL back" do
      pending! "needs a real tty" unless STDOUT.tty?
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.set_mode(Termisu::Terminal::Mode::CrToNl)

      tios = uninitialized LibC::Termios
      LibC.tcgetattr(STDOUT.fd, pointerof(tios)).should eq(0)
      (tios.c_iflag & LibC::ICRNL).should_not eq(0)
    ensure
      termios.try &.restore
    end
  end
end
