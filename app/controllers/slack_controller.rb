require 'json'
require 'httparty'


class SlackController < ApplicationController
  skip_before_action :verify_authenticity_token

  include SnackHelper

  BANNER_TEXT = 'Vote on your favorite snacks'.freeze
  ATTACHMENT_TYPE = 'default'.freeze
  ATTACHMENT_COLOR = '#3AA3E3'.freeze
  ATTACHMENT_VOTE_CALLBACK_ID = 'vote'.freeze
  ATTACHMENT_FALLBACK = 'You are unable to choose a snack'.freeze

  def vote
    add_vote_using_payload

    render json: {
      text: BANNER_TEXT,
      message_ts: params[:message_ts],
      attachments: get_attachment_info
    }
  end

  def receive
    case command
      when 'snacklist'
        respond_to do |format|
          format.json {
            render json: {
              response_type: 'in_channel',
              text: BANNER_TEXT,
              "attachments": get_attachment_info
            }
          }
        end
      when 'suggest'
        respond_to do |format|
          add_vote_using_command do |status|
            if status[:success]
              format.json {
                render json: {
                  text: "Successfully added snack *#{status[:snackname]}*"
                }
                send_updated_list
              }
            else
              format.json {
                render json: {
                  text: "This snack cannot be added *#{status[:snackname]}*"
                }
              }
            end
          end
        end
    end
  end

  private

  def send_updated_list
    url = URI.parse(ENV['SLACK_WEBHOOK_URL'])
    res = HTTParty.post(url.to_s, body: {
      text: BANNER_TEXT,
      attachments: get_attachment_info
    }.to_json, headers: { 'Content-Type': 'application/json' })
  end

  def get_attachment_info
    snack_list
  end

  def snack_list
    sorted_snacks.map do |snack|
      name = snack[:name]
      vote_count_yes = snack[:vote_count_yes]
      vote_count_no = snack[:vote_count_no]
      display_name = name.capitalize
      {
        text: display_name,
        fallback: ATTACHMENT_FALLBACK,
        callback_id: ATTACHMENT_VOTE_CALLBACK_ID,
        color: ATTACHMENT_COLOR,
        attachment_type: ATTACHMENT_TYPE,
        vote_count_yes: vote_count_yes,
        actions: [
          {
            name: name,
            text: vote_count_yes.to_s,
            type: 'button',
            style: 'primary',
            value: 1
          },
          {
            name: name,
            text: vote_count_no.to_s,
            type: 'button',
            style: 'danger',
            value: -1
          },
          {
            name: name,
            text: 'Undo my vote',
            type: 'button',
            value: 0
          }
        ]
      }
    end
      .select { |entry| entry[:vote_count_yes] > 0 }
  end

  def add_vote_using_payload
    payload = JSON.parse(params[:payload])
    payload_action = payload['actions'].first
    username = payload['user']['name']
    snackname = payload_action['name']
    add_vote(username: username, snackname: snackname, value: payload_action['value'])
  end

  def add_vote_using_command
    username = params[:user_name]
    snackname = params[:text]
    if add_vote(username: username, snackname: snackname, value: 1)
      yield(success: true, snackname: snackname)
    else
      yield(success: false, snackname: snackname)
    end
  end

  def add_vote(username:, snackname:, value:)
    user = find_or_create_user(username)
    snack = find_or_create_snack(snackname)
    vote = Vote.find_by(user_id: user.id, snack_id: snack.id)
    if vote
      vote.value = value
    else
      vote = Vote.new(user_id: user.id, snack_id: snack.id, value: value)
    end
    vote.save
  end

  def find_or_create_user(username)
    user = User.find_by(username: username)
    unless user
      user = User.new(username: username)
      user.save
    end
    user
  end

  def find_or_create_snack(snackname)
    snack = Snack.find_by(name: snackname)
    unless snack
      snack = Snack.new(name: snackname)
      snack.save
    end
    snack
  end

  def command
    params[:command].sub('/', '')
  end
end
