require 'sinatra'
require 'sinatra/reloader' if development?
require File.dirname(__FILE__) + '/cue_sheet'

get '/' do
  content_type :text
  @cue_sheet = CueSheet.new
  erb :index
end

