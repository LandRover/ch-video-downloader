#!/usr/bin/ruby -w

require 'rubygems'
require 'fileutils'
require 'net/http'
require 'nokogiri'
require 'ruby-progressbar'

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


class CH
    @url = ''
    @useragent = ''
    @tmp_downloades = ''


    def initialize(params = {})
        @url = params.fetch(:url, '')
        @useragent = params.fetch(:useragent, '')
        @tmp_downloades = params.fetch(:tmp, convert_url_to_tmp_folder('./downloads/', @url))

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

            return tmp.concat(uri.path.gsub('/', '-').slice(1, url.length))
        end


        def load_videos()
            videos = get_videos_list()

            return download(videos)
        end


        def download(videos)
            File.open("#{@tmp_downloades}/.meta", 'w') { |file| file.write("Title: #{videos[:title]}\nPublisher: #{videos[:publisher]}\nEpisodes:#{videos[:list]}\n") }

            videos[:list].each do |name, url|
                download_file(name, url, "#{@tmp_downloades}/#{name}");
            end

            log('INFO', "Done downloading: #{@url}")
        end


        def download_file(file_name, url, dist)
            uri = URI.parse(url)

            begin
                @counter = 0

                Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
                  response = http.request_head(uri.path)
                  file_size = response['content-length'].to_i

                  if File.file?(dist) && file_size === File.size(dist) then
                      log('WARN', "[#{file_name}] already exists, skipping...");
                      next
                  end

                  log('INFO', "[#{file_name}] Starting to download from #{url}")

                  @pbar = ProgressBar.create(
                        :title => file_name,
                        :total => file_size,
                        :rate_scale => lambda { |rate| rate * 200 },
                        :format => "%a %b\u{15E7}%i %p%% %t",
                        :progress_mark  => '-',
                        :remainder_mark => "\u{FF65}")

                  File.open(dist, 'w') {|f|
                     http.get(uri.path) do |str|
                       f.write str
                       @counter += str.length
                       @pbar.progress = @counter
                     end
                   }

                  @pbar.finish

                  log('INFO', "[#{file_name}] Finished Downloading.")
                end
	    rescue Net::OpenTimeout => e
                  log('ERROR', "OpenTimeout exception [#{e}]! oh-noes!")
	    rescue Timeout::Error => te
                  log('ERROR', "Timeout exception [#{te}]! oh-noes!")
            rescue => e
                  log('ERROR', "Caught exception [#{e}]! oh-noes!")
            end
        end


        def get_videos_list()
            page = get_ch_page()
            videos_selector = page.css('ul#lessons-list li')
            title = page.css('div.original-name').text
            publisher = page.css('header a').text

            videos = {
                title: sanitizeString(title),
                publisher: sanitizeString(publisher),
                list: {}
            }

            videos_selector.each_with_index do |video, index|
                text = video.css('div.lessons-name').text
                video_url = video.css('link[itemprop="url"]')[0]['href']
                file_extension = File.extname(video_url)

                video_title = "#{index+1} - #{text}#{file_extension}"
                video_title = sanitizeString(video_title)

                if 1 === video_title.index(' - ') then
                    video_title.prepend('0')
                end

                videos[:list][video_title] = video_url
            end

            return videos
        end


        def get_ch_page()
            markup = get_html_markup(@url, @useragent);
            page = Nokogiri::HTML(markup)

            return page
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

            return FileUtils.mkdir_p(dir) unless File.exist?(dir)
        end


        def sanitizeString(string)
            return string
                    .gsub('&amp;', '&')
                    .gsub(' : ', ' - ')
                    .gsub(': ', ' - ')
                    .gsub('. ', ' - ')
                    .gsub('  ', ' ')
                    .gsub('?', '')
                    .gsub(' .mp4', '.mp4')
                    .gsub(' .webm', '.webm')
                    .gsub('"', "'")
                    .gsub('/', ', ')
        end

        ## Genric way to print verbose
        def log(lvl, text)
            puts "[#{lvl}]: #{text}"
        end
end

ch = CH.new(:url => url, :useragent => useragent)
ch.start()
