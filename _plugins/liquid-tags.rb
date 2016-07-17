module ExtractSynopsis
  def extract_synopsis(input)
    first_index = input.index('<p>')
    second_index = input.index('<p>', first_index + 1)
    third_index = input.index('</p>', second_index + 1)
    return input[first_index..(third_index + 4)]
  end
end

Liquid::Template.register_filter(ExtractSynopsis)
