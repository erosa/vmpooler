require 'spec_helper'
require 'rack/test'

module Vmpooler
  class API
    module Helpers
      def authenticate(auth, username_str, password_str)
        username_str == 'admin' and password_str == 's3cr3t'
      end
    end
  end
end

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  describe '/vm' do
    let(:prefix) { '/api/v1' }

    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
        },
        pools: [
          {'name' => 'pool1', 'size' => 5},
          {'name' => 'pool2', 'size' => 10}
        ],
        alias: { 'poolone' => 'pool1' },
      }
    }

    let(:current_time) { Time.now }

    before(:each) do
      redis.flushdb

      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /vm' do
      it 'returns a single VM' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'returns a single VM for an alias' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'

        post "#{prefix}/vm", '{"poolone":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistant pools' do
        post "#{prefix}/vm", '{"poolpoolpool":"1"}'
        expect_json(ok = false, http = 404)
      end

      it 'returns multiple VMs' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'
        create_ready_vm 'pool2', 'qrstuvwxyz012345'

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          },
          pool2: {
            hostname: 'qrstuvwxyz012345'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context '(auth not configured)' do
        it 'does not extend VM lifetime if auth token is provided' do
          app.settings.set :config, auth: false

          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime']).to be_nil
        end
      end

      context '(auth configured)' do
        it 'extends VM lifetime if auth token is provided' do
          app.settings.set :config, auth: true

          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime'].to_i).to eq(2)
        end

        it 'does not extend VM lifetime if auth token is not provided' do
          app.settings.set :config, auth: true
          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}'
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime']).to be_nil
        end
      end
    end
  end
end
