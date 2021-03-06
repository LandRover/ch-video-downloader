#!/usr/bin/ruby -w

require 'json'
require 'rubygems'
require 'fileutils'
require 'net/http'
require 'nokogiri'
require 'ruby-progressbar'

url = ''
update = false


def usage(s)
    $stderr.puts(s)
    $stderr.puts("Usage: #{File.basename($0)}: <-url http://ch.io/class/title> [-update]")
    exit(2)
end


loop { case ARGV[0]
    when '-url' then  ARGV.shift; url = ARGV.shift
    when '-update' then  ARGV.shift; update = true
    when /^-/ then  usage("Unknown option: #{ARGV[0].inspect}")
    else break
end; }


class CH
    @@useragent = 'Mozilla/5.0'
    
    @@cookiesList = {
    }


    def initialize(params = {})
        log('DEBUG', "CH Initialized (#{params})");
    end


    def download_update(params = {})
        log('INFO', "Starting Update Download... (#{params})");

        url = get_url_from_metadata()

        if (url == nil)
            url = params.fetch(:url, nil)
        end

        throw :missingURLForCourse if (url == nil || url == '')
        
        log('INFO', "Detected URL of a course from metadata: (#{url})");

        videos = get_videos_list(url)
        download_videos(videos)
    end


    def download_new(params = {})
        url = params.fetch(:url, '')
        
        log('INFO', "Starting New Download... (#{params})");
        
        videos = get_videos_list(url)
        
        folder = "#{videos[:title]} (#{videos[:publisher]}) (AUTHOR) (#{videos[:date_release]})"
        dst = "./downloads/#{folder}"
        createDir(dst)
        
        download_videos(videos, dst)
    end
    

    private
        def get_url_from_metadata(dst = '.')
            return get_url_from_metadata_JSON(dst)
        end


        def get_url_from_metadata_JSON(dst = '.')
            meta_file = "#{dst}/.metadata.json"
            url = nil

            if (!File.exist?(meta_file))
                return url
            end

            begin
                file = File.read(meta_file);
                videos_metadata = JSON.parse(file)
                
                url = videos_metadata['url']
            rescue => e
                log('ERROR', "Caught exception [#{e}]! oh-noes!")
            end

            return url
        end


        def get_url_from_metadata_TEXT(dst)
            meta_file = "#{dst}/.meta"

        end


        def create_meta_file(videos, dst = '.')
            meta_file = "#{dst}/.metadata.json"
            
            begin
                log('DEBUG', "Creating metadata file: #{meta_file}")
                
                File.open(meta_file, 'w') { |file| file.write(JSON.pretty_generate(videos)) }
            rescue => e
                log('ERROR', "Caught exception [#{e}]! oh-noes!")
            end
        end


        def download_attachments(attachment_url, dst = '.')
            unless (attachment_url.nil? || attachment_url.end_with?("zip")) then
                log('DEBUG', "Downloading course attachments: #{attachment_url}")
                
                codeFilename = 'code.zip'
                download_file(codeFilename, attachment_url, "#{dst}/#{codeFilename}")
            end
        end


        def download_videos(videos, dst = '.')
            create_meta_file(videos, dst)
            download_attachments(videos[:url_code], dst)
            
            videos[:list].each do |name, url|
                download_file(name, url, "#{dst}/#{name}");
            end

            log('INFO', "Course: #{videos[:title]}")
            log('INFO', "URL: #{videos[:url]}")
            log('INFO', "Done downloading.")
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


        def get_videos_list(url)
            page = get_ch_page(url)
            log('DEBUG', "Page download completed")

            log('DEBUG', "Extracting JSON from page")
            myPlayerArr = page.to_s.split('file: ')[2].split('poster:')[0].to_s[0..-32] + ']'
            videos_list = JSON.parse(myPlayerArr)
            log('DEBUG', "JSON converted to MAP successfully")
            
            log('DEBUG', "Formatting map and converting to internal structure...")
            title = page.css('p.hero-description').text
            publisher = page.css('a.course-box-value').text
            date_added = page.css('.course-box .course-box-item .course-box-value')[3].text.strip

            begin
                url_code = page.css('a.btn[href*="code"]')[0]['href']
            rescue
                url_code = nil
            end
            
            begin
                date_release = page.css('.course-box .course-box-item .course-box-value')[5].text.strip
            rescue
                date_release = "_" + date_added + "_"
            end

            videos = {
                title: sanitizeString(title),
                date_now: Time.now.strftime("%d/%m/%Y %H:%M"),
                date_added: sanitizeString(date_added.gsub('/', '-')),
                date_release: sanitizeString(date_release.gsub('/', '-')),
                publisher: sanitizeString(publisher),
                url: url,
                url_code: url_code,
                list: {}
            }
            
            videos_list.each_with_index do |video, index|
                text = video['title'].gsub(/^([0-9]{1,2})\) /, "").gsub(/ \| .*/, "")
                video_url = video['file']
                file_extension = File.extname(video_url)

                video_title = "#{index+1} - #{text}#{file_extension}"
                video_title = sanitizeString(video_title)

                if 1 === video_title.index(' - ') then
                    video_title.prepend('0')
                end

                videos[:list][video_title] = video_url
            end

            log('DEBUG', "Formatting completed, videos map ready...")

            return videos
        end


        def get_ch_page(url)
            log('DEBUG', "Downloading course page")

            markup = get_html_markup(url, @@useragent, @@cookiesList);
            page = Nokogiri::HTML(markup)

            return page
        end


        ## Creates HTTP request and returns Markup string
        def get_html_markup(url, useragent, cookiesList)
            log('INFO', "Downloading HTML document markup for #{url}")

            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true

            cookies = cookiesList.map { |key, value| "#{key}=#{value}" }
            
            req = Net::HTTP::Get.new(uri.path, {
                'User-Agent' => useragent,
                'Cookie' => cookies.join(';')
            })
            response = http.request(req)

            return response.body
        end


        def createDir(dir)
            log('DEBUG', "Creating folder: '#{dir}'")

            return FileUtils.mkdir_p(dir) unless File.exist?(dir)
        end


        def sanitizeString(string)
            return string
                .gsub(/\s+/, ' ')
                .gsub(/(\?|!)/, '')
                .gsub('&amp;', '&')
                .gsub(/(&#039;|"|&quot;)/, "'")
                .gsub(/( : |: |\. )/, ' - ')
                .gsub(/(:)/, '-')
                .gsub(' .mp4', '.mp4')
                .gsub(' .webm', '.webm')
                .gsub(/(\/|\\)/, ', ')
                .gsub(' , ', ', ')
                .gsub(/\s+/, ' ')
                .strip
        end

        ## Genric way to print verbose
        def log(lvl, text)
            puts "[#{lvl}]: #{text}"
        end
end

ch = CH.new()
ch.download_update(:url => url) if update == true
ch.download_new(:url => url) if update == false
