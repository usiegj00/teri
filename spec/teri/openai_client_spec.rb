require 'spec_helper'
require 'teri/openai_client'
require 'teri/accounting'

RSpec.describe Teri::OpenAIClient do
  let(:api_key) { 'test_api_key' }
  let(:model) { 'gpt-3.5-turbo' }
  let(:client) { described_class.new(api_key: api_key, model: model) }
  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:transaction) { instance_double(Teri::Transaction) }
  let(:entry) { instance_double(Teri::Entry, amount: 100.0, currency: 'USD') }
  let(:accounting) { instance_double(Teri::Accounting) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(transaction).to receive_messages(
      description: 'PAYMENT *ACME INC',
      date: '2023-01-01',
      entries: [entry],
      counterparty: 'ACME INC',
      memo: nil,
      hints: []
    )

    allow(accounting).to receive(:respond_to?).with(:previous_codings).and_return(true)
    allow(accounting).to receive(:respond_to?).with(:counterparty_hints).and_return(true)
    allow(accounting).to receive_messages(previous_codings: {}, counterparty_hints: {})

    # Add respond_to? stubs for all methods that might be checked
    allow(transaction).to receive(:respond_to?).and_return(false)
    allow(transaction).to receive(:respond_to?).with(:description).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:date).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:entries).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:counterparty).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:memo).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:hints).and_return(true)
    allow(transaction).to receive(:respond_to?).with(:amount).and_return(false)
  end

  describe '#initialize' do
    it 'initializes with an API key' do
      expect(client.client).to eq(openai_client)
    end

    it 'uses the provided model' do
      expect(client.model).to eq(model)
    end

    it 'raises an error if no API key is provided' do
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return(nil)
      expect { described_class.new }.to raise_error(RuntimeError)
    end
  end

  describe '#suggest_category' do
    let(:response) do
      {
        'choices' => [
          {
            'message' => {
              'content' => '{"category": "Expenses:Office", "confidence": 0.9, "explanation": "This is a payment to ACME Inc, which is likely an office supply vendor."}',
            },
          },
        ],
      }
    end

    before do
      allow(openai_client).to receive(:chat).and_return(response)
    end

    it 'calls the OpenAI API with the correct parameters' do
      expect(openai_client).to receive(:chat) do |params|
        expect(params[:parameters][:model]).to eq(model)
        expect(params[:parameters][:messages].first[:content]).to include('PAYMENT *ACME INC')
        response
      end

      client.suggest_category(transaction, accounting)
    end

    it 'returns a hash with the suggested category' do
      result = client.suggest_category(transaction, accounting)
      expect(result[:category]).to eq('Expenses:Office')
      expect(result[:confidence]).to eq(0.9)
      expect(result[:explanation]).to include('ACME Inc')
    end

    context 'when the API returns invalid JSON' do
      let(:response) do
        {
          'choices' => [
            {
              'message' => {
                'content' => 'This is not valid JSON',
              },
            },
          ],
        }
      end

      it 'returns a default category with zero confidence' do
        result = client.suggest_category(transaction, accounting)
        expect(result[:category]).to eq('Expenses:Unknown')
        expect(result[:confidence]).to eq(0)
        expect(result[:explanation]).to include('Failed to parse')
      end
    end

    context 'with previous codings' do
      let(:previous_codings) do
        {
          'PAYMENT *ACME INC' => { category: 'Expenses:Office', hints: ['Office supplies'] },
        }
      end

      before do
        allow(accounting).to receive(:previous_codings).and_return(previous_codings)
      end

      it 'includes previous codings in the prompt' do
        expect(openai_client).to receive(:chat) do |params|
          expect(params[:parameters][:messages].first[:content]).to include('Previous codings')
          expect(params[:parameters][:messages].first[:content]).to include('"PAYMENT *ACME INC" => Expenses:Office')
          response
        end

        client.suggest_category(transaction, accounting)
      end
    end

    context 'with counterparty hints' do
      let(:counterparty_hints) do
        {
          'ACME INC' => ['Office supplies vendor', 'Monthly subscription'],
        }
      end

      before do
        allow(accounting).to receive(:counterparty_hints).and_return(counterparty_hints)
      end

      it 'includes counterparty hints in the prompt' do
        expect(openai_client).to receive(:chat) do |params|
          expect(params[:parameters][:messages].first[:content]).to include('Counterparty information')
          expect(params[:parameters][:messages].first[:content]).to include('Office supplies vendor')
          response
        end

        client.suggest_category(transaction, accounting)
      end
    end
  end

  describe '#build_prompt' do
    before do
      allow(transaction).to receive(:respond_to?).with(:entries).and_return(true)
      allow(transaction).to receive_messages(description: 'New Transaction', counterparty: 'Test Vendor',
                                             entries: [entry])
    end

    it 'includes the current transaction details in the prompt' do
      prompt = client.build_prompt(transaction, accounting)
      expect(prompt).to include('Description: New Transaction')
      expect(prompt).to include('Counterparty: Test Vendor')
    end

    context 'with previous transactions' do
      let(:previous_codings) do
        {
          'Previous Transaction' => {
            category: 'Expenses:Office',
            hints: ['office supplies'],
          },
        }
      end

      let(:counterparty_hints) do
        {
          'Test Vendor' => ['office supplies vendor'],
        }
      end

      before do
        allow(accounting).to receive_messages(previous_codings: previous_codings,
                                              counterparty_hints: counterparty_hints)
      end

      it 'includes previous transactions with the same counterparty' do
        prompt = client.build_prompt(transaction, accounting)
        expect(prompt).to include('Previous codings')
        expect(prompt).to include('"Previous Transaction" => Expenses:Office')
        expect(prompt).to include('Counterparty information')
        expect(prompt).to include('office supplies vendor')
      end
    end
  end
end
