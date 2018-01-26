# encoding: utf-8
require 'sinatra'
require 'slim'
require 'yaml'
require 'redcarpet'
require 'rouge'
require 'sass'

set :root, File.join(File.dirname(__FILE__), '..')
set(:views) { File.join(root, 'lib', 'views') }

set :public_folder, File.join(File.dirname(__FILE__), '/static')

set(:css_dir) { File.join(public_folder, 'css') }
set(:js_dir) { File.join(public_folder, 'js') }

get '/' do
  slim :index
end

get '/css/terminal.css' do
  scss :'sass/terminal'
end

get '/remarkjs' do
  remark current_page('remarkjs')
end

def remark(page)
  Slim::Template.new("#{settings.views}/remarkjs.slim", { disable_escape: true }).render(self) do
    page.markdown
  end
end

get '/revealjs' do
  reveal current_page('revealjs')
end

def reveal(page)
  Slim::Template.new("#{settings.views}/revealjs.slim", { disable_escape: true }).render(self) do
    page.render
  end
end

def current_page(engine = 'revealjs')
  @current_page ||= Page.new(engine,request.env['HTTP_HOST'])
end

def canonical_link_tag(url)
  "<link rel='canonical' href='#{url}' />"
end

def css_path(file)
  File.join('/css',file)
end

def stylesheet_link_tag(css_path)
  "<link id='#{css_path}' rel='stylesheet' type='text/css' href='#{css_path}'>"
end

def js_path(file)
  File.join('/js',file)
end

def javascript_include_tag(name)
  "<script type='text/javascript' src='#{name}'></script>"
end

class NoPage
  def to_s
    "I am not a page!"
  end
end

class Page
  def initialize(name,base_url)
    @name = name
    @base_url = base_url
    @front_matter, @presentation_content = extract_front_matter(File.read(path))
  end

  def url
    "http://#{@base_url}/#{@name}"
  end

  def title
    @front_matter.title
  end

  def content
    @presentation_content
  end

  def extract_front_matter(content)
    front_matter, presentation_content = content.split(/^---$/u,2)
    [ FrontMatter.parse(front_matter), presentation_content ]
  end

  def path
    # TODO: provide support so that it will run this one when working with it locally, but using this other one when inside habitat. This could be detected by the env or either are checked for when performed.
    "presentation-#{@name}.html.rmd.erb"
    # "source/presentations/presentation.html.rmd.erb"
  end

  class Helpers
    def get_binding
      binding
    end

    # TODO: This does not work
    def unstyled_list(&block)
      "<ul style='list-style-type: none;'>#{instance_eval(&block)}</ul>"
    end

    # TODO: This does not work
    def icon_list_item(foundation_icon, &block)
      "<li><i class='fa fa-#{foundation_icon}' style='min-width: 21px;'></i>&nbsp;#{instance_eval(&block)}</li>"
    end

    def fp(filepath)
      "`#{filepath}`"
    end
  end

  class VegasRender < Redcarpet::Render::XHTML
    def preprocess(full_document)
      MarkdownParser.parse_document full_document
    end
  end

  # Take the content and process it for ERB, then split up the slides, then
  # run it through a markdown parser that cares a little more about your code
  # blocks and then finally stitch it all back up.
  def render
    local_content = @presentation_content.force_encoding(Encoding::UTF_8)

    erb_render = ERB.new(local_content)
    results = erb_render.result(Helpers.new.get_binding)

    renderer = VegasRender.new({fenced_code_blocks: true, smartypants: false, tables: true, escape_html: false })
    markdown = Redcarpet::Markdown.new(renderer, extensions = {})

    #     - process it for slide markers
    results.split('<!-- SLIDE -->').map do |slide|
      "<section>\n#{markdown.render(slide)}</section>"
    end.join
  end

  def markdown
    local_content = @presentation_content.force_encoding(Encoding::UTF_8)

    erb_render = ERB.new(local_content)
    results = erb_render.result(Helpers.new.get_binding)

    renderer = VegasRender.new({fenced_code_blocks: true, smartypants: false, tables: true, escape_html: false })
    markdown = Redcarpet::Markdown.new(renderer, extensions = {})

    #     - replace our SLIDE indicator with the one supported by remark
    results.split('<!-- SLIDE -->').map { |slide| markdown.render(slide) }.join("\n\n---\n\n")
  end


end

class FrontMatter
  def self.parse(content)
    new YAML.load(content)
  end

  def initialize(content)
    @content = content
  end

  def title
    @content['title']
  end
end

module MarkdownParser
  # Evaluate the entire document and look code blocks:
  #
  #     ```LANGUAGE METADATA
  #     CODE
  #     ```
  def self.parse_document(full_document)
    full_document.gsub /^\s{0,4}`{3}.+?`{3}/m do |code_block|
      parse_code_block code_block
    end
  end

  # Extract from the code block the metadata and the code and highlight it.
  #
  #     ```LANGUAGE METADATA
  #     CODE
  #     ```
  #
  def self.parse_code_block(code_block)
    code_block.gsub /(\s{0,4})`{3}([^\n]+)?\n(.+?)`{3}\Z/m do
      spacing = Regexp.last_match(1)
      spacing = (spacing == "\n" ? "" : spacing)
      metadata = get_metadata(Regexp.last_match(2).to_s)
      code = Regexp.last_match(3).to_s
      trimmed_code = code.gsub("\n#{spacing}","\n")[spacing.length..-1]
      "\n#{spacing}#{Highlighter.highlight(trimmed_code, metadata)}"
    end
  end

  AllOptions = /([^\s]+)\s+(.+?)\s+(https?:\/\/\S+|\/\S+)\s*(.+)?/i
  LangCaption = /([^\s]+)\s*(.+)?/i

  # Extract the metadata from the code block. There are two simple formats:
  #
  #     ```LANGUAGE TITLE
  #
  #     ```LANGUAGE TITLE URL LINK_TEXT
  #
  #
  def self.get_metadata(markup)
    defaults = { escape: true }
    clean_markup = OptionsParser.new(markup).clean_markup

    if clean_markup =~ AllOptions
      defaults = {
        lang: $1,
        title: $2,
        url: $3,
        link_text: $4,
      }
    elsif clean_markup =~ LangCaption
      defaults = {
        lang: $1,
        title: $2
      }
    end
    OptionsParser.new(markup).parse_markup(defaults)
  end
end

class OptionsParser
  attr_accessor :input

  def initialize(markup)
    @input = markup.strip
  end

  def clean_markup
    input.sub(/\s*lang:\s*\S+/i,'')
      .sub(/\s*title:\s*(("(.+?)")|('(.+?)')|(\S+))/i,'')
      .sub(/\s*url:\s*(\S+)/i,'')
      .sub(/\s*link_text:\s*(("(.+?)")|('(.+?)')|(\S+))/i,'')
      .sub(/\s*mark:\s*\d\S*/i,'')
      .sub(/\s*linenos:\s*\w+/i,'')
      .sub(/\s*start:\s*\d+/i,'')
      .sub(/\s*end:\s*\d+/i,'')
      .sub(/\s*range:\s*\d+-\d+/i,'')
      .sub(/\s*escape:\s*\w+/i,'')
      .sub(/\s*startinline:\s*\w+/i,'')
      .sub(/\s*class:\s*(("(.+?)")|('(.+?)')|(\S+))/i,'')
  end

  def parse_markup(defaults = {})
    options = {
      lang:      lang,
      url:       url,
      title:     title,
      linenos:   linenos,
      marks:     marks,
      link_text: link_text,
      start:     start,
      end:       endline,
      escape:    escape,
      startinline: startinline,
      class:     classnames
    }
    options = options.delete_if { |k,v| v.nil? }
    defaults.merge(options)
  end

  def lang
    extract(/\s*lang:\s*(\S+)/i)
  end

  def startinline
    boolize(extract(/\s*startinline:\s*(\w+)/i))
  end

  def classnames
    extract(/\s*class:\s*(("(.+?)")|('(.+?)')|(\S+))/i, [3, 5, 6])
  end

  def url
    extract(/\s*url:\s*(("(.+?)")|('(.+?)')|(\S+))/i, [3, 5, 6])
  end

  def title
    extract(/\s*title:\s*(("(.+?)")|('(.+?)')|(\S+))/i, [3, 5, 6])
  end

  def linenos
    boolize(extract(/\s*linenos:\s*(\w+)/i))
  end

  def escape
    boolize(extract(/\s*escape:\s*(\w+)/i))
  end

  # Public: Matches pattern for line marks and returns array of line
  #         numbers to mark
  #
  # Example input
  #   Input:  "mark:1,5-10,2"
  #   Output: [1,2,5,6,7,8,9,10]
  #
  # Returns an array of integers corresponding to the lines which are
  #   indicated as marked
  def marks
    marks = []
    if input =~ / *mark:(\d\S*)/i
      marks = $1.gsub /(\d+)-(\d+)/ do
        ($1.to_i..$2.to_i).to_a.join(',')
      end
      marks = marks.split(',').collect {|s| s.to_i}.sort
    end
    marks
  end

  def link_text
    extract(/\s*link[-_]text:\s*(("(.+?)")|('(.+?)')|(\S+))/i, [3, 5, 6], 'link')
  end

  def start
    if range
      range.first
    else
      num = extract(/\s*start:\s*(\d+)/i)
      num = num.to_i unless num.nil?
      num
    end
  end

  def endline
    if range
      range.last
    else
      num = extract(/\s*end:\s*(\d+)/i)
      num = num.to_i unless num.nil?
      num
    end
  end

  def range
    if input.match(/ *range:(\d+)-(\d+)/i)
      [$1.to_i, $2.to_i]
    end
  end

  def extract(regexp, indices_to_try = [1], default = nil)
    thing = input.match(regexp)
    if thing.nil?
      default
    else
      indices_to_try.each do |index|
        return thing[index] if thing[index]
      end
    end
  end

  def boolize(str)
    return nil if str.nil?
    return true if str == true || str =~ (/(true|t|yes|y|1)$/i)
    return false if str == false || str =~ (/(false|f|no|n|0)$/i) || str.strip.size > 1
    return str
  end
end

module Highlighter
  def self.options
    @options ||= {}
  end

  def self.options=(value)
    @options = value
  end

  # The highlight method is called when code fences are used in RedCarpet
  # and when the code helper is used.
  #
  # @param code [String] the content found within the code block
  # @param options [Hash] contains any additional rendering options provided
  #    to the code helper methods, as code fences don't have a way to
  #    provide additional parameters.
  #
  # @return the HTML that will be rendered to the page
  def self.highlight(code, metadata={})
    return no_html if code_block_is_empty?(code.strip)
    metadata[:lang] = with_lang_aliases_considered(metadata[:lang])
    TableFormatter.new.render(code, metadata)
  end

  def self.code_block_is_empty?(code)
    code == "" || code == "</div>"
  end

  def self.no_html
    ""
  end

  # When languages are provided they could be aliases for other languages
  # or the way that they are presented. With a few languages we want to
  # make sure that they are presented within the context of a console.
  def self.with_lang_aliases_considered(lang)
    case lang
    when 'cmd'
      'console?lang=powershell'
    when 'posh', 'powershell', 'shell', 'studio'
      "console?lang=#{lang}"
    when 'ps1'
      'powershell'
    else
      lang
    end
  end

end

class TableFormatter
  def render(code, metadata)
    lexer = Rouge::Lexer.find_fancy(metadata[:lang], code) || Rouge::Lexers::PlainText
    lexed_code = expand_tokens_with_newlines(lexer.lex(code, {}))

    formatter = Rouge::Formatters::HTML.new(wrap: false)
    rendered_code = formatter.format(lexed_code)
    rendered_code = tableize_code(rendered_code, metadata)

    classnames = [ 'code-highlight-figure', metadata[:class].to_s ].join(' ')

    "<figure class='#{classnames}'>#{caption(metadata)}#{rendered_code}</figure>"
  end

  # The lexed code generates an enumerator of tokens with their values.
  # Before they are rendered to HTML all of the non-text tokens with newlines
  # should be split into several tokens of the same type. This ensures
  # that when they are tableized later the surrounding spans are not broken.
  def expand_tokens_with_newlines(lexed_code)
    full_lex = []
    lexed_code.each do |token, value|
      if %w[ Text Text.Whitespace ].include? token.qualname
        full_lex << [ token, value ]
      else
        lines = value.split("\n")
        lines.each_with_index do |line, index|
          # if not the last line or the last line had a newline at the end
          suffix = if index < (lines.length - 1) || (index == (lines.length - 1) && value.end_with?("\n"))
            "\n"
          else
            ""
          end

          full_lex << [ token, "#{line}#{suffix}" ]
        end
      end
    end
    full_lex
  end

  # Given the rendered code it is time to present the information in a table.
  def tableize_code(code, options)
    start = options[:start] || 1
    lines = options[:linenos] || false
    marks = options[:marks]

    table = "<div class='code-highlight'>"
    table += "<pre class='code-highlight-pre'>"
    code.lines.each_with_index do |line,index|
      classes = 'code-highlight-row'
      classes += lines ? ' numbered' : ' unnumbered'
      if marks.include? index + start
        classes += ' marked-line'
        classes += ' start-marked-line' unless marks.include? index - 1 + start
        classes += ' end-marked-line' unless marks.include? index + 1 + start
      end
      line = line.strip.empty? ? ' ' : line
      table += "<div data-line='#{index + start}' class='#{classes}'><div class='code-highlight-line'>#{line}</div></div>"
    end
    table +="</pre></div>"
  end

  # Generates a caption above the code area when there is a title / url
  def caption(options)
    if options[:title]
      figcaption  = "<figcaption class='code-highlight-caption'><span class='code-highlight-caption-title'>#{options[:title]}</span>"
      figcaption += "<a class='code-highlight-caption-link' href='#{options[:url]}'>#{(options[:link_text] || 'link').strip}</a>" if options[:url]
      figcaption += "</figcaption>"
    else
      ''
    end
  end

end
