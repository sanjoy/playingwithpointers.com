module ExtractSynopsis
  def extract_synopsis(input)
    first_index = input.index('<p>')
    second_index = input.index('<p>', first_index + 1)
    third_index = input.index('</p>', second_index + 1)
    return input[first_index..(third_index + 4)]
  end
end

Liquid::Template.register_filter(ExtractSynopsis)

class HNLink < Liquid::Tag
  def initialize(tag_name, link, tokens)
    @link = link
    super
  end

  def render(context)
    "Discussion on Hacker News: <#{@link}>. However, I'd prefer if the more substantive comments (e.g. pointing out fundamental mistakes or an interesting future direction) are made here and not on Hacker News."  end
end

Liquid::Template.register_tag('hnlink', HNLink)
