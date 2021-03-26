# frozen_string_literal: true

class HTX
  def self.compile(path, content)
    "[htx:compile #{path.inspect}, #{content.inspect}]"
  end
end
