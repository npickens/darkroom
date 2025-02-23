# frozen_string_literal: true

require_relative('test_helper')

class HTXDelegateTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Compile                                                                                              ##
  ##########################################################################################################

  test('compiles content using the HTX library') do
    path = '/template.htx'
    content = '<div>${this.hello}</div>'
    asset = new_asset(path, content)

    HTX.stub(:compile, lambda do |*args|
      assert_equal(path, args[0])
      assert_equal(content, args[1])

      '[compiled]'
    end) do
      asset.process
    end

    refute_error(asset.errors)
    assert_equal('[compiled]', asset.content)
  end

  test('does not pass :as_module argument to HTX.compile if HTX::VERSION is undefined') do
    asset = new_asset('/template.htx', '<div>${this.hello}</div>')

    HTX.stub(:compile, lambda do |*, **options|
      refute(options.key?(:as_module))

      '[compiled]'
    end) do
      asset.process
    end

    refute_error(asset.errors)
    assert_equal('[compiled]', asset.content)
  end

  test('does not pass :as_module argument to HTX.compile if HTX::VERSION is earlier than 0.1.1') do
    [nil, %w[0.0.1 0.0.2 0.0.3 0.0.4 0.0.5 0.0.6 0.0.7 0.0.8 0.0.9 0.1.0]].flatten.each do |version|
      asset = new_asset('/template.htx', '<div>${this.hello}</div>')

      HTX.const_set(:VERSION, version) if version

      HTX.stub(:compile, lambda do |*args|
        if version
          assert(defined?(HTX::VERSION), "Expected HTX::VERSION to be '#{version}'")
        else
          refute(defined?(HTX::VERSION), 'Expected HTX::VERSION to be nil')
        end

        refute(args.last.key?(:as_module)) if args.last.kind_of?(Hash)

        '[compiled]'
      end) do
        asset.process
      end

      refute_error(asset.errors)
      assert_equal('[compiled]', asset.content)
    ensure
      HTX.send(:remove_const, :VERSION) if defined?(HTX::VERSION)
    end
  end

  test('passes :as_module argument to HTX.compile if HTX::VERSION is 0.1.1 or later') do
    %w[0.1.1 0.1.2 1.0.0 1.1.0 1.1.1].each do |version|
      asset = new_asset('/template.htx', '<div>${this.hello}</div>')

      HTX.const_set(:VERSION, version)

      HTX.stub(:compile, lambda do |*args|
        assert(defined?(HTX::VERSION), "Expected HTX::VERSION to be '#{version}'")
        assert_kind_of(Hash, args.last)
        assert(args.last.key?(:as_module))

        '[compiled]'
      end) do
        asset.process
      end

      refute_error(asset.errors)
      assert_equal('[compiled]', asset.content)
    ensure
      HTX.send(:remove_const, :VERSION) if defined?(HTX::VERSION)
    end
  end
end
