module ExtractSynopsis
  def extract_synopsis(input)
    first_index = input.index('<p>')
    if first_index == nil
      return ''
    end
    second_index = input.index('<p>', first_index + 1)
    if second_index == nil
      return ''
    end
    third_index = input.index('</p>', second_index + 1)
    if third_index == nil
      return ''
    end
    return input[first_index..(third_index + 4)]
  end
end

module EscapeLiquidTags
  def escape_liquid_tags(input)
    return input.gsub('{\%', '&#123;%')
  end
end

Liquid::Template.register_filter(ExtractSynopsis)
Liquid::Template.register_filter(EscapeLiquidTags)

class HNLink < Liquid::Tag
  def initialize(tag_name, link, tokens)
    @link = link
    super
  end

  def render(context)
    "<br/><br/><br/>Discussion on Hacker News: <#{@link}>. However, I'd prefer if the more substantive comments (e.g. pointing out fundamental mistakes or an interesting future direction) are made here and not on Hacker News."  end
end

Liquid::Template.register_tag('hnlink', HNLink)
