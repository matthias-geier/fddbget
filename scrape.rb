require "parser_girl"
require "net/http"
require "cgi"
require "htmlentities"

module Scrape
  extend self

  SEARCH_URL = "https://fddb.info/db/de/suche/?udd=0&cat=site-de&search=%{term}"

  def search(needle)
    needle, args = split_args(needle)
    needle = needle.join(" ")
    url = SEARCH_URL % {term: CGI.escape(needle.encode("iso-8859-1"))}
    resp = Net::HTTP.get_response(URI(url))
    if resp.is_a?(Net::HTTPSuccess)
      pg = ParserGirl.new(resp.body)
      table = pg.find("table").detect do |elem|
        cols = elem.find("td")
        next ["Sehr beliebt", "Beliebt", "Normal"].any? do |e|
          cols.content.any? { |c| c.strip == e }
        end
      end
      food = table.find("tr").reduce([]) do |acc, elem|
        cols = elem.find("td")
        if cols.count > 1
          acc << cols.to_a[1].find("a")&.to_h&.first&.[](:href)
        end
        next acc
      end.compact
      food =
        if args.key?(:num)
          food[[args[:num], food.count].min - 1]
        else
          food[0]
        end
    elsif resp.is_a?(Net::HTTPRedirection)
      food = resp["location"]
    end
    return food ? yield(food) : {status: "error", reason: "no food found"}
  end

  def split_args(needle)
    return needle.split(" ").reduce([[], {}]) do |(elems, args), str|
      if str =~ /^num:(\d+)$/
        args[:num] = $1.to_i
      else
        elems << str
      end
      next elems, args
    end
  end

  def decode(str)
    str.force_encoding("iso-8859-1").encode("UTF-8")
  end

  def extract(food_url)
    body = Net::HTTP.get(URI(food_url))
    pg = ParserGirl.new(body)
    data = pg.find("div").reduce({}) do |acc, div|
      next acc unless div.to_h[:class] == "standardcontent"
      next acc.merge(
        titel: title(pg),
        marke: brand(pg),
        image: image(pg),
        url: food_url,
        naehrwerte: nutrition(div),
        options: options(pg)
      ).merge(details(div))
    end
    return data
  end

  def title(container)
    return container.find("h1").reduce(nil) do |acc, h1|
      next acc unless h1.to_h[:id] == "fddb-headline1"
      next HTMLEntities.new.decode(decode(h1.content))
    end
  end

  def brand(container)
    return container.find("h2").reduce(nil) do |acc, h2|
      next acc unless h2.to_h[:id] == "fddb-headline2"
      next HTMLEntities.new.decode(decode(h2.find("a").content.first))
    end
  end

  def image(container)
    return container.find("img").reduce(nil) do |acc, img|
      next acc if acc || !img.to_h[:class]&.include?("imagesimpleborder")
      next img.to_h[:src]
    end
  end

  def nutrition(container)
    return container.find("h2").reduce(nil) do |acc, h2|
      next acc unless decode(h2.content).include?("Nährwerte")
      amount, unit = h2.content.match(/(\d+) ([a-z]+)/).captures
      next {amount: amount.to_i, unit: unit}
    end
  end

  def details(container)
    fields = ["Kalorien", "Protein", "Kohlenhydrate", "davon Zucker", "Fett"]
    return fields.reduce({}) do |acc, field|
      acc[field.downcase.gsub(" ", "_").to_sym] = detail(container, field)
      next acc
    end
  end

  def detail(container, field)
    return container.find("div").reduce(nil) do |acc, div|
      name = div.find("div").first&.find("a")&.content
      if name.nil? || name.empty?
        name = div.find("div").first&.find("span")&.content
      end
      next acc unless name == field
      value = div.find("div").content.last
      next value.match(/([\d,]+)/).captures.first.sub(/,/, ".").to_f
    end
  end

  def options(container)
    return container.find("a").reduce([]) do |acc, a|
      next acc unless a.to_h[:class] == "servb"
      name, weight = a.content.match(/^(.*) \(([\d,]+)\s+\S+\)$/)&.captures
      next acc if name.nil?
      next acc << {
        name: HTMLEntities.new.decode(decode(name)),
        weight: weight.sub(/,/, ".").to_f
      }
    end
  end
end
