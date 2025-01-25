# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('asset_test')

class DelegateTest < Minitest::Test
  include(TestHelper)

  test('validates import regex to ensure required named captures are present') do
    error = assert_raises(RuntimeError) do
      Darkroom.register('.ext') do
        import(/no captures/)
      end
    end

    assert_error('#<RuntimeError: Import regex is missing required named captures: quote, path>', error)
  end
  test('validates reference regex to ensure required named captures are present') do
    error = assert_raises(RuntimeError) do
      Darkroom.register('.ext') do
        reference(/no captures/)
      end
    end

    assert_error(
      '#<RuntimeError: Reference regex is missing required named captures: quote, path, quoted, entity, ' \
        'format>',
      error
    )
  end
end
