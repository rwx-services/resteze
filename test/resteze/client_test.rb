require "test_helper"

module Resteze
  class ClientTest < Minitest::Spec
    subject { AcmeApi::Client }

    describe ".proxy_options" do
      subject { AcmeApi::Client.proxy_options }

      it "should return nil when no proxy is configured" do
        AcmeApi.proxy = nil

        assert_nil subject
      end

      it "should return the Farday::ProxyOptions when configured" do
        AcmeApi.proxy = "https://user:pass@proxy.example.com:9292"

        assert_instance_of Faraday::ProxyOptions, subject
        assert_equal "user", subject.user
        assert_equal "pass", subject.password
        assert_equal "proxy.example.com", subject.host
        assert_equal "https", subject.scheme
        assert_equal 9292, subject.port
      end
    end

    describe ".client_name" do
      it "should be the name of the Client class converted to underscores" do
        assert_equal "acme_api/client", subject.client_name
      end
    end

    describe "#client_name" do
      it "should be the name of the Client class converted to underscores" do
        assert_equal "acme_api/client", subject.new.client_name
      end
    end

    describe ".api_module" do
      it "should be the parent namespace of the client" do
        assert_same AcmeApi, subject.api_module
      end
    end

    describe "#api_module" do
      it "should be the parent namespace of the client" do
        assert_same AcmeApi, subject.new.api_module
      end
    end

    describe ".logger" do
      it "should be the same as root API's logger" do
        assert_same AcmeApi.logger, subject.logger
      end
    end

    describe "#logger" do
      it "should be the same as root API's logger" do
        assert_same AcmeApi.logger, subject.new.logger
      end
    end

    describe ".util" do
      it "should be the same as root API's Util" do
        assert_same AcmeApi::Util, subject.util
      end
    end

    describe "#util" do
      it "should be the same as root API's Util" do
        assert_same AcmeApi::Util, subject.new.util
      end
    end

    describe ".active_client" do
      it "should be .default_client outside of #request" do
        assert_equal subject.default_client, subject.active_client
      end

      it "should be active client inside of #request" do
        client = subject.new

        client.request do
          assert_equal client, subject.active_client
        end
      end
    end

    describe ".default_client" do
      it "should be a Resteze::Client" do
        assert_kind_of Resteze::Client, subject.default_client
        assert_instance_of AcmeApi::Client, subject.default_client
      end

      it "should be a different client on each thread" do
        other_thread_client = nil
        thread = Thread.new do
          other_thread_client = subject.default_client
        end
        thread.join

        refute_equal subject.default_client, other_thread_client
      end
    end

    describe ".default_connection" do
      it "should be a Faraday::Connection" do
        assert_kind_of Faraday::Connection, subject.default_connection
      end

      it "should be a different connection on each thread" do
        other_thread_conn = nil
        thread = Thread.new do
          other_thread_conn = subject.default_connection
        end
        thread.join

        refute_equal subject.default_connection, other_thread_conn
      end
    end

    describe ".faraday_adapter" do
      it "should be a valid Faraday adapter" do
        assert_match "net_http", subject.faraday_adapter
      end
    end

    describe "#initialize" do
      it "should set default_connection" do
        client = subject.new

        assert_equal subject.default_connection, client.connection
      end

      it "should set a different connection if one was specified" do
        connection = Faraday.new
        client = subject.new(connection)

        assert_equal connection, client.connection
      end
    end

    describe "#execute_request" do
      describe "given a JSON endpoint" do
        before do
          stub_request(:post, api_url("/account"))
            .to_return(body: JSON.generate(object: "account"))
        end

        it "should assume and response with parsed JSON" do
          assert_equal({ object: "account" }, subject.new.execute_request(:post, "/account").data)
        end

        it "should include default headers" do
          subject.new.execute_request(:post, "/account")

          assert_requested(
            :post,
            api_url("/account"),
            headers: { "Accept" => "application/json", "Content-Type" => "application/json" }
          ) do |req|
            user_agent = req.headers["User-Agent"]
            user_agent =~ %r{Ruby/.* Faraday/.* \(net_http\) Resteze/.* AcmeApi/.*}
          end
        end

        it "should support literal headers and include default headers" do
          subject.new.execute_request(:post, "/account", headers: { "Resteze-Account" => "bar" })

          assert_requested(
            :post,
            api_url("/account"),
            headers: { "Accept" => "application/json", "Content-Type" => "application/json",
                       "Resteze-Account" => "bar" }
          )
        end

        it "should support RestClient-style header keys" do
          subject.new.execute_request(:post, "/account", headers: { resteze_account: "bar" })

          assert_requested :post, api_url("/account"), headers: { "Resteze-Account" => "bar" }
        end
      end

      describe "given an XML endpoint" do
        before do
          stub_request(:get, api_url("/account"))
            .to_return(body: "<account>value</account>", headers: { "content-type" => "application/xml" })
        end

        it "should response with parsed XML" do
          assert_equal({ account: "value" }, subject.new.execute_request(:get, "/account").data)
        end
      end

      describe "given an HTML endpoint" do
        before do
          stub_request(:get, api_url("/account"))
            .to_return(body: "<html></html>", headers: { "content-type" => "text/html" })
        end

        it "should response with raw HTML" do
          assert_equal("<html></html>", subject.new.execute_request(:get, "/account").data)
        end
      end
    end

    describe "params serialization" do
      before do
        stub_request(:get, api_url("/invoices/upcoming"))
          .with(query: hash_including(customer: "cus_123"))
          .to_return(body: JSON.generate(object: "account"))
      end

      it "should allows empty strings in params" do
        subject.new.execute_request(:get, "/invoices/upcoming", params: { customer: "cus_123", coupon: "" })

        assert_requested(:get, api_url("/invoices/upcoming"), query: { customer: "cus_123", coupon: "" })
      end

      it "should filter nils in params" do
        subject.new.execute_request(:get, "/invoices/upcoming", params: { customer: "cus_123", coupon: nil })

        assert_requested(:get, api_url("/invoices/upcoming"), query: { customer: "cus_123" })
      end
    end

    describe "#request" do
      before do
        stub_request(:get, api_url("/widgets/1"))
          .to_return(body: JSON.generate(object: "widget"))
      end

      it "should return a result and response object" do
        account, resp = subject.new.request { AcmeApi::Widget.retrieve("1") }

        assert_instance_of AcmeApi::Widget, account
        assert_instance_of AcmeApi::Response, resp
        assert_kind_of Resteze::Response, resp
        assert_equal 200, resp.http_status
      end

      it "should return the value of given block" do
        ret, = subject.new.request { 7 }

        assert_equal 7, ret
      end

      it "should reset local thread state after a call" do
        Thread.current["acmeapi/client"] = :new_client
        subject.new.request { AcmeApi::Widget.retrieve("1") }

        assert_equal :new_client, Thread.current["acmeapi/client"]
      ensure
        Thread.current["acmeapi/client"] = nil
      end

      it "should raise JSON::ParserError on invalid response" do
        stub_request(:get, api_url("/charges")).to_return(body: "invalid json")

        assert_raises JSON::ParserError do
          subject.new.execute_request(:get, "/charges")
        end
      end
    end

    describe ".api_url" do
      before { @old_api_base = subject.api_module.api_base }
      after { subject.api_module.api_base = @old_api_base }

      it "should format correctly with a slash" do
        subject.api_module.api_base = "http://www.example.com/investor/"

        assert_equal "http://www.example.com/investor/foo", subject.api_url("/foo")
      end

      it "should format correctly without a slash" do
        subject.api_module.api_base = "http://www.example.com/investor/"

        assert_equal "http://www.example.com/investor/foo", subject.api_url("/foo")
      end
    end
  end
end
