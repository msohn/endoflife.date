# This script creates API files for version 1 of the endoflife.date API.
#
# There are two kind of generated files :
# - all.json: contains endoflife metadata, such as the list of all the products and the product count.
# - <product>.json: contains a given product data (including releases data).

require 'jekyll'

module ApiV1

  STRIP_HTML_BLOCKS = Regexp.union(
    /<script.*?<\/script>/m,
    /<!--.*?-->/m,
    /<style.*?<\/style>/m
  )
  STRIP_HTML_TAGS = /<.*?>/m

  # Remove HTML from a string (such as an LTS label).
  # This is the equivalent of Liquid::StandardFilters.strip_html, which cannot be used
  # unfortunately.
  def self.strip_html(input)
    empty = ''.freeze
    result = input.to_s.gsub(STRIP_HTML_BLOCKS, empty)
    result.gsub!(STRIP_HTML_TAGS, empty)
    result
  end

  class ApiGenerator < Jekyll::Generator
    safe true
    priority :lowest

    TOPIC = "API v1:"

    def generate(site)
      @site = site
      Jekyll.logger.info TOPIC, "Generating..."

      add_index_page(site)
      product_pages = add_product_pages(site)
      add_all_products_page(site, product_pages)

      add_category_pages(site, product_pages)
      add_all_categories_page(site, product_pages)

      add_tag_pages(site, product_pages)
      add_all_tags_page(site, product_pages)
      Jekyll.logger.info TOPIC, "Generation done."
    end

    private

    def add_index_page(site)
      site_url = site.config['url']
      site.pages << JsonPage.new(site, '/', 'index', {
        result: [
          { name: "products", uri: "#{site_url}/api/v1/products/" },
          { name: "categories", uri: "#{site_url}/api/v1/categories/" },
          { name: "tags", uri: "#{site_url}/api/v1/tags/" },
        ]
      })
    end

    def add_product_pages(site)
      product_pages = []

      site.pages.each do |page|
        if page.data['layout'] == 'product'
          product_pages << page
          site.pages << ProductJsonPage.new(site, page)

          site.pages << ProductCycleJsonPage.new(site, page, page.data['releases'][0], 'latest')
          page.data['releases'].each do |cycle|
            site.pages << ProductCycleJsonPage.new(site, page, cycle)
          end
        end
      end

      return product_pages
    end

    def add_all_products_page(site, products)
      site.pages << ProductsJsonPage.new(site, '/products/', 'index', products)
    end

    def add_category_pages(site, products)
      pages_by_category = {}

      products.each do |product|
        category = product.data['category'] || 'unknown'
        add_to_map(pages_by_category, category, product)
      end

      pages_by_category.each do |category, products|
        site.pages << ProductsJsonPage.new(site, "/categories/#{category}", 'index', products)
      end
    end

    def add_all_categories_page(site, products)
      site.pages << JsonPage.new(site, '/categories/', 'index', {
        result: products
                  .map { |product| product.data['category'] }
                  .uniq
                  .sort
                  .map { |category| { name: category, uri: "#{site.config['url']}/api/v1/categories/#{category}/" } }
      })
    end

    def add_tag_pages(site, products)
      products_by_tag = {}

      products.each do |product|
        product.data['tags'].each { |tag| add_to_map(products_by_tag, tag, product) }
      end

      products_by_tag.each do |tag, products|
        site.pages << ProductsJsonPage.new(site, "/tags/#{tag}", 'index', products)
      end
    end

    def add_all_tags_page(site, products)
      site.pages << JsonPage.new(site, '/tags/', 'index', {
        result: products
                  .flat_map { |product| product.data['tags'] }
                  .uniq
                  .sort
                  .map { |tag| { name: tag, uri: "#{site.config['url']}/api/v1/tags/#{tag}/" } }
      })
    end

    def add_to_map(map, key, page)
      if map.has_key? key
        map[key] << page
      else
        map[key] = [page]
      end
    end
  end

  class JsonPage < Jekyll::Page
    def initialize(site, path, name, data)
      @site = site
      @base = site.source
      @dir = "api/v1#{path}"
      @name = "#{name}.json"
      @data = {}
      @data['layout'] = 'json'
      @data['data'] = data

      self.process(@name)
    end
  end

  class ProductsJsonPage < JsonPage
    def initialize(site, path, name, products)
      super(site, path, name, {
        total: products.size(),
        products: products.map { |product| {
          name: product.data['id'],
          label: product.data['title'],
          category: product.data['category'],
          tags: product.data['tags'],
          uri: "#{site.config['url']}/api/v1/products/#{product.data['id']}/",
        } }
      })
    end
  end

  class ProductJsonPage < JsonPage
    def initialize(site, product)
      id = product.data['id']
      super(site, "/products/#{id}", 'index', {
        name: id,
        label: product.data['title'],
        category: product.data['category'],
        tags: product.data['tags'],
        links: {
          icon: product.data['iconUrl'],
          html: "#{site.config['url']}/#{id}",
          releasePolicyLink: product.data['releasePolicyLink'],
        },
        versionCommand: product.data['versionCommand'],
        # https://github.com/gjtorikian/jekyll-last-modified-at/blob/master/lib/jekyll-last-modified-at/determinator.rb
        lastModified: product.data['last_modified_at'].last_modified_at_time.iso8601,
        auto: product.data.has_key?('auto'),
        cycles: [
          product.data['releases']
                 .map { |cycle| {
                   name: cycle['releaseCycle'],
                   codename: cycle['codename'],
                   label: ApiV1.strip_html(cycle['label']),
                   date: cycle['releaseDate'],
                   support: cycle['support'],
                   lts: cycle['lts'],
                   eol: cycle['eol'],
                   discontinued: cycle['discontinued'],
                   extendedSupport: cycle['extendedSupport'],
                   latest: {
                     version: cycle['latest'],
                     date: cycle['latestReleaseDate'],
                     link: cycle['link'],
                   }
                 } }
        ]
      })
    end
  end

  class ProductCycleJsonPage < JsonPage
    def initialize(site, product, cycle, identifier = nil)
      name = identifier ? identifier : cycle['id']

      super(site, "/products/#{product.data['id']}/cycles/#{name}", 'index', {
        name: cycle['releaseCycle'],
        codename: cycle['codename'],
        label: ApiV1.strip_html(cycle['label']),
        date: cycle['releaseDate'],
        support: cycle['support'],
        lts: cycle['lts'],
        eol: cycle['eol'],
        discontinued: cycle['discontinued'],
        extendedSupport: cycle['extendedSupport'],
        latest: {
          version: cycle['latest'],
          date: cycle['latestReleaseDate'],
          link: cycle['link'],
        }
      })
    end
  end
end
