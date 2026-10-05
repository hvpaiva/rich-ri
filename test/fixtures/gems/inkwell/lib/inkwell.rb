# frozen_string_literal: true

# A well of ink. Its operators are the method names a shell and a line editor
# find hardest to complete.
class Inkwell
  # Fill the well.
  def fill; end

  # Report whether the well is full.
  def filled?; end

  # Name the ink.
  def name=(value); end

  # Read a pigment.
  def [](key); end

  # Store a pigment.
  def []=(key, value); end

  # Add ink.
  def <<(ink); end

  # Compare the level of two wells.
  def <=(other); end

  # Order two wells.
  def <=>(other); end

  # Compare two wells.
  def ==(other); end

  # Match a well in a case expression.
  def ===(other); end

  # Match the name of the ink.
  def =~(other); end
end
