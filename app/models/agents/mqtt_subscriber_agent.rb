# encoding: utf-8 
require "json"

module Agents
  class MqttSubscriberAgent < Agent
    include LongRunnable

    cannot_be_scheduled!
    cannot_receive_events!

    gem_dependency_check { defined?(MQTT) }

    description <<-MD
      The MQTT Subscriber Agent allows subscription to an MQTT topic.

      #{'## Include `mqtt` in your Gemfile to use this Agent!' if dependencies_missing?}

      MQTT is a generic transport protocol for machine to machine communication.

      Simply choose a topic (think email subject line) to listen to, and configure your service.

      It's easy to setup your own [broker](http://jpmens.net/2013/09/01/installing-mosquitto-on-a-raspberry-pi/) or connect to a [cloud service](http://www.cloudmqtt.com)

      Hints:
      Many services run mqtts (mqtt over SSL) often with a custom certificate.

      You'll want to download their cert and install it locally, specifying the ```certificate_path``` configuration.


      Example configuration:

      <pre><code>{
        'uri' => 'mqtts://user:pass@localhost:8883'
        'ssl' => :TLSv1,
        'ca_file' => './ca.pem',
        'cert_file' => './client.crt',
        'key_file' => './client.key',
        'topic' => 'huginn'
      }
      </code></pre>

      Subscribe to CloCkWeRX's TheThingSystem instance (thethingsystem.com), where
      temperature and other events are being published.

      <pre><code>{
        'uri' => 'mqtt://kcqlmkgx:sVNoccqwvXxE@m10.cloudmqtt.com:13858',
        'topic' => 'the_thing_system/demo'
      }
      </code></pre>

      Subscribe to all topics
      <pre><code>{
        'uri' => 'mqtt://kcqlmkgx:sVNoccqwvXxE@m10.cloudmqtt.com:13858',
        'topic' => '/#'
      }
      </code></pre>

      Find out more detail on [subscription wildcards](http://www.eclipse.org/paho/files/mqttdoc/Cclient/wildcard.html)
    MD

    event_description <<-MD
      Events are simply nested MQTT payloads. For example, an MQTT payload for Owntracks

      <pre><code>{
        "topic": "owntracks/kcqlmkgx/Dan",
        "message": {"_type": "location", "lat": "-34.8493644", "lon": "138.5218119", "tst": "1401771049", "acc": "50.0", "batt": "31", "desc": "Home", "event": "enter"},
        "time": 1401771051
      }</code></pre>
    MD

    def validate_options
      unless options['uri'].present? &&
             options['topic'].present?
        errors.add(:base, "topic and uri are required")
      end
    end

    def working?
      (event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?) || received_event_without_error?
    end

    def default_options
      {
        'uri' => 'mqtts://user:pass@localhost:8883',
        'ssl' => :TLSv1,
        'ca_file'  => './ca.pem',
        'cert_file' => './client.crt',
        'key_file' => './client.key',
        'topic' => 'huginn',
        'expected_update_period_in_days' => '2'
      }
    end

    def process_message(topic, payload)
      create_event payload: {
        'topic' => topic,
        'message' => payload,
        'time' => Time.now.to_i
      }
    end

    protected

    class Worker < LongRunnable::Worker
      RELOAD_TIMEOUT = 60.minutes

      def setup
        mqtt_client.connect
      end

      def run
        EventMachine.run do
          EventMachine.add_periodic_timer(RELOAD_TIMEOUT) do
            restart!
          end
          mqtt_client.get_packet(agent.interpolated['topic']) do |packet|
            topic, payload = message = [packet.topic, packet.payload]

            # A lot of services generate JSON, so try that.
            begin
              payload = JSON.parse(payload)
            rescue
            end
            
            AgentRunner.with_connection do
              agent.process_message(topic, payload)
            end

          end
        end
        Thread.stop
      end

      def stop
        EventMachine.stop_event_loop if EventMachine.reactor_running?
        mqtt_client.disconnect
        terminate_thread!
      end

      private
      def mqtt_client
        @client ||= begin
          MQTT::Client.new(agent.interpolated['uri']).tap do |c|
            if agent.interpolated['ssl']
              c.ssl = agent.interpolated['ssl'].to_sym
              c.ca_file = agent.interpolated['ca_file']
              c.cert_file = agent.interpolated['cert_file']
              c.key_file = agent.interpolated['key_file']
            end
          end
        end
      end
    
    end

  end
end
