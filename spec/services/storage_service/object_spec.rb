require 'rails_helper'

RSpec.describe StorageService::Object do

  let(:photo) { build :photo }
  let(:object_key) { photo.object_key }
  let(:bucket) { 'emporium' }
  subject { described_class.new(object_key) }

  before do
    allow(StorageService).to receive(:bucket).and_return(bucket)
    Aws.config[:s3] = { stub_responses: true }
  end

  describe '#url' do
    it 'generates an url for the object' do
      expect(subject.url).to start_with "https://#{bucket}.s3.amazonaws.com/#{object_key}"
    end
  end

  describe '#delete' do
    it 'deletes an object' do
      expect(subject.delete).to be_an_instance_of(Seahorse::Client::Response)
    end
  end

end
