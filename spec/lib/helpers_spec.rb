require 'spec_helper'

describe Ott::Helpers do
  it 'check root' do
    expect(Ott::Helpers.root.class).to eq Pathname
    expect(Ott::Helpers.root.to_s).to eq Dir.pwd
  end

  it 'chef diffed_lines' do
    expect(Ott::Helpers.diffed_lines('').empty?).to eq true
    diff = <<-BODY
@@ -38,9 +38,7 @@ module Ott
@@ -58,23 +56,6 @@ module Ott
    BODY
    expect(Ott::Helpers.diffed_lines(diff)).to match_array [38..45, 56..62]
  end

  it 'stores data to local file' do
    some_data       = 'OTT-12' # sample issue
    custom_filename = 'some_file2.txt'
    full_path       = File.join(Dir.pwd, custom_filename)
    double          = StringIO.new
    allow(File).to receive(:open).with(full_path, 'w+').and_yield(double)
    allow(File).to receive(:size).with(full_path)

    Ott::Helpers.export_to_file(some_data, custom_filename)
    expect(double.string).to eq(some_data)
  end
end
