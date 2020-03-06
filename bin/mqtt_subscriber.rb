#!/usr/bin/env ruby

# TODO

require_relative './pre_runner_boot'

AgentRunner.new(only: Agents::MqttAgent).run