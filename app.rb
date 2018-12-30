require 'sinatra'
require 'sinatra/reloader' if development?
require File.dirname(__FILE__) + '/cue_sheet'

get '/' do
  erb :index
end

get '/cue_sheet' do
  content_type :text
  @cue_sheet = CueSheet.load(params[:sheet_url], params[:base_cell].split(',', 2).map(&:to_i))
  erb :cue_sheet
end

