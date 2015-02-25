require 'twitter_ebooks'
require 'rss'
require 'nokogiri'
require 'open-uri'

# Read the Awl's RSS feed and post links to new items in the style of @AwlTags
class AwlBot < Ebooks::Bot

  attr_accessor :url, :cache, :model

  def configure
    # setup feed url
    @url = 'http://feeds2.feedburner.com/TheAwl'
    # path to cache file
    @cache = ENV['HOME'] + '/AwlTagsCache.txt'
    @model = Ebooks::Model.load('model/AwlTags.model')
  end

  def on_startup
    scheduler.every '1h' do
      # check for and post items every hr
      post_items
    end
  end

  def on_mention(tweet)
    # Reply to a mention
    relevant_words = tweet[:text]
    length = meta[:reply_prefix].length
    response = @model.make_response(relevant_words , 140 - length)
    if response 
      reply(tweet, meta[:reply_prefix] + response)
    else
      log ("Unable to form dynamic response.")
    end 
  end

  def on_startup
    # post items
    post_items
  end

  def post_items
    log "Posting items..."
    rss = RSS::Parser.parse(@url)
    rss.items.each do |item|
      #get the document
      url = item.link
      shortlink = item.guid.content #the awl uses their shorlinks as guid now?
      begin
        data = open(url)
      rescue OpenURI::HTTPError => e
        log "Problem opening " + url + " " + e.message
        return
      end
      doc = Nokogiri::HTML(data)
      #check to see if tweet already posted?
      unless already_posted(shortlink)
        if just_the_awl(shortlink)
          tags = ''
          if shortlink
            #determine the remaining characters left after shortlink (with space)
            link_length = shortlink.length + 1
            #get tags (adding each one until we have 140 char tweet)
            doc.css('.g-tag-box ul li a').each do |match|
              #format the tag
              tag = ' ' + match.content.to_s.upcase + ','
              #bail if we are too long (1 = remove end comma)
              unless (link_length + tags.length + tag.length - 1) >= 140
                #add to tags
                tags << tag
              end
            end
            #trim and remove trailing comma
            tweet = tags[0..-2].strip + ' ' + shortlink
          end
          #tweet is valid
          if (shortlink && tags.length >= 2)
            self.tweet(tweet)
            #add to cache
            set_as_posted(shortlink)
          end
        end
      end
    end
  end

  def already_posted(link)
    #returns true if link appears in cache
    results = []
    if (File.exists?(@cache))
      f = File.new(cache, "r")
      f.each { |line| results << line.chomp }
    end
    return results.include?(link)
  end

  def just_the_awl(link)
    #returns true if this is an awl link vs others
    return /www\.theawl\.com/.match(link)
  end

  def set_as_posted(link)
    #adds the link to the cache
    f = File.new(@cache, "a+")
    f.puts link
  end
 
end

#Configure and launch bot using foreman provieded .env variables
AwlBot.new(ENV['BOT_NAME']) do |bot|
  bot.consumer_key = ENV['CONSUMER_KEY']
  bot.consumer_secret = ENV['CONSUMER_SECRET']
  bot.access_token = ENV['ACCESS_TOKEN']
  bot.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
end
