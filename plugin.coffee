async = require 'async'
fs = require 'fs'
path = require 'path'
_ = require 'lodash'
yaml = require 'js-yaml'
url = require 'url'
marked = require 'marked'

module.exports = (wintersmith, callback) ->

  order = require process.cwd()+"/order.yml"
  articleOrderMap = {}
  index = 0
  order.forEach (chapter) ->
    if _.isObject chapter
      title = (Object.keys chapter)[0]
      articleOrderMap[ "#{title}/index.html" ] = ++index
      for article in chapter[title]
        articleOrderMap["#{title}/#{article}.html"] = ++index;
    else
      articleOrderMap[ "#{chapter}.html" ] = ++index

  is_relative = (uri) ->
    ### returns true if *uri* is relative; otherwise false ###
    !/(^\w+:)|(^\/)/.test uri

  getPageOrdinalPosition = (filename) ->
    articleOrderMap[ filename ] ? 0

  parseMetadata = (filename, metadata, callback) ->
    ### takes *metadata* in the format:
          key: value
          foo: bar
        returns parsed object ###
    rv = {}
    try
      lines = metadata.split '\n'

      for line in lines
        pos = line.indexOf ':'
        key = line.slice(0, pos).toLowerCase().trim()
        value = line.slice(pos + 1).trim()
        rv[key] = value

      callback null, rv

    catch error
      callback error

  extractMetadata = (content, filename, base, callback) ->
    # split metadata and markdown content
    split_content = content.split("---")

    try
      if split_content.length >= 2
        [metadata, markdown]  = [split_content[1].trim(), split_content.slice(2).join("\n").trim()]
      else
        throw "'#{filename}' does not have any metadata."
    catch err
      return callback err

    async.parallel
      metadata: (callback) ->
        parseMetadata filename, metadata, callback
      markdown: (callback) ->
        callback null, markdown
    , callback

  parseMarkdownSync = (content, baseUrl) ->
    ### takes markdown *content* and returns html using *baseUrl* for any relative urls
        returns html ###

    marked.inlineLexer.formatUrl = (uri) ->
      if is_relative uri
        return url.resolve baseUrl, uri
      else
        return uri
    marked content

  class OrderedMarkdownPage extends wintersmith.defaultPlugins.MarkdownPage
    render: (locals, contents, templates, callback) ->
      super locals, contents, templates, ( error, result ) ->
        # we have to slice off the first item in the buffer which seems to be a linebreak
        callback error, result.slice 1

    @property 'template', ->
      if @_metadata
        @_metadata.template or 'default.jade'
      else
        'none'

    @property 'title', ->
      @_metadata.title

    @property 'order', ->
      getPageOrdinalPosition @filename

    getFilename: ->
      [p...,file] = @_filename.split path.sep or "/"
      if p.length and file == "index.md"
        "#{path.join.apply null, p}.html"
      else
        super

    getHtml: (base) ->
      ### parse @markdown and return html. also resolves any relative urls to absolute ones ###
      @_html ?= parseMarkdownSync @_content, @getLocation(base) # cache html
      return @_html

  OrderedMarkdownPage.fromFile = (filename, base, callback) ->
    async.waterfall [
      (callback) ->
        fs.readFile path.join(base, filename), callback
      (buffer, callback) ->
        extractMetadata buffer.toString(), filename, base, callback
      (result, callback) =>
        {markdown, metadata} = result
        page = new this filename, markdown, metadata
        callback null, page
    ], callback
   
  wintersmith.registerContentPlugin 'pages', '**/*.md', OrderedMarkdownPage
  callback() # tell the plugin manager we are done
