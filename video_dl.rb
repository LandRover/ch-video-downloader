#!/usr/bin/ruby -w

require 'net/http'
require 'pp'
require 'ruby-progressbar'

require 'rubygems'
require 'nokogiri'

url = ''
useragent = 'Mozilla/5.0 (Linux; U; Android 2.3.4; en-us; Nexus S Build/GRJ22) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1'

def usage(s)
    $stderr.puts(s)
    $stderr.puts("Usage: #{File.basename($0)}: <-u http://ch.io/class/title>")
    exit(2)
end

loop { case ARGV[0]
    when '-u' then  ARGV.shift; url = ARGV.shift
    when /^-/ then  usage("Unknown option: #{ARGV[0].inspect}")
    else break
end; }

## Deep merge 2 hashes
public
def deep_merge(p)
    m = proc { |key,v,vv| v.class == Hash && vv.class == Hash ? v.merge(vv, &m) : vv }
    merge(p, &m)
end

class CH
    @url = ''
    @useragent = ''
    @tmp_downloades = ''
    

    def initialize(params = {})
        @url = params.fetch(:url, '')
        @useragent = params.fetch(:useragent, '')
        @tmp_downloades = params.fetch(:tmp, convert_url_to_tmp_folder('./tmp/', @url))
        
        createDir(@tmp_downloades)

		puts @tmp_downloades
    end
    

    def start
        log('INFO', "Starting #{@url}");
        
        load_videos();
    end

    private
        def convert_url_to_tmp_folder(tmp, url)
            uri = URI.parse(url)

            return tmp + uri.path.gsub('/', '-').slice(1, url.length)
        end
    
    
        def load_videos()
            videos = get_videos_list()

            return download(videos)
        end
        
        
        def download(videos)
            videos.each do |name, url|
                download_file(name, url, @tmp_downloades + '/' + name);
            end
            
            log('INFO', 'Done downloading: ' + @url)
        end
        
        
        def download_file(file_name, url, dist)
            uri = URI.parse(url)
            
            @counter = 0
            
            Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
              response = http.request_head(uri.path)
              file_size = response['content-length'].to_i
              
              if File.file?(dist) && file_size === File.size(dist) then
                  log('WARN', "File #{file_name} already exists, skipping...");
                  next
              end
              
              
              @pbar = ProgressBar.create(
                    :format => "%a %b\u{15E7}%i %p%% %t",
                    :progress_mark  => ' ',
                    :remainder_mark => "\u{FF65}")
              @pbar.total = file_size

              File.open(dist, 'w') {|f|
                 http.get(uri.path) do |str|
                   f.write str
                   @counter += str.length
                   @pbar.progress = @counter
                 end
               }
               
              @pbar.finish
              
              log('INFO', 'Downloaded '+ url)
            end
        end
        
        
        def get_videos_list()
            videos = {}
            videos_selector = get_html_videos()
            
            videos_selector.each do |video|
                text = video.css('span[itemprop="name"]').text
                url = video.css('link[itemprop="url"]')[0]['href']
                file_extension = File.extname(url)
                
                
                title = text
                    .slice(5...text.length)
                    .gsub('&amp;', '&')
                    .gsub(': ', ' - ')
                    .gsub('. ', ' - ')
                    .concat(file_extension)

                if 1 === title.index(' - ') then
                    title.prepend('0')
                end
                
                videos[title] = url
            end
            
            return videos
        end

        
        def get_html_videos()
            markup = get_html_markup(@url, @useragent);
            page = Nokogiri::HTML(markup)
            videos_items = page.css('ul#lessons-list li');
            
            return videos_items
        end
        
        
        ## Creates HTTP request and returns Markup string
        def get_html_markup(url, useragent)
            log('INFO', "Getting Markup for #{url}")
            
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true

            req = Net::HTTP::Get.new(uri.path, {
                'User-Agent' => useragent
            })
            response = http.request(req)
    
            return response.body
        end
        
        
        def createDir(dir)
            log('DEBUG', "Creating dir #{dir}")
            
            return FileUtils.mkdir_p(dir) unless File.exists?(dir)
        end
        
        ## Genric way to print verbose
        def log(lvl, text)
            puts "[#{lvl}]: #{text}"
        end
end

ch = CH.new(:url => url, :useragent => useragent)
ch.start()