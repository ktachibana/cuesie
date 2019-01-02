require 'bundler'
Bundler.require

require 'sinatra'
require 'sinatra/reloader' if development?
require File.dirname(__FILE__) + '/cue_sheet'

get '/' do
  haml :index
end

get '/cue_sheet' do
  @cue_sheet = CueSheet.load(params[:sheet_url])
  haml :cue_sheet
end

get '/cue_sheet.sass' do
  sass :cue_sheet
end
