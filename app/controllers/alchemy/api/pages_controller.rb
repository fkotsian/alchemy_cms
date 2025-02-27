# frozen_string_literal: true

module Alchemy
  class Api::PagesController < Api::BaseController
    serialization_scope :current_ability
    before_action :load_page, only: [:show]

    # Returns all pages as json object
    #
    def index
      # Fix for cancancan not able to merge multiple AR scopes for logged in users
      if can? :edit_content, Alchemy::Page
        @pages = Alchemy::Page.all
      else
        language = Alchemy::Language.find_by(id: params[:language_id]) || Alchemy::Language.current
        @pages = Alchemy::Page.accessible_by(current_ability, :index)
        @pages = @pages.where(language: language)
      end
      @pages = @pages.includes(*page_includes)
      @pages = @pages.ransack(params[:q]).result

      if params[:page]
        @pages = @pages.page(params[:page]).per(params[:per_page])
      end

      render json: @pages, adapter: :json, root: "pages", meta: meta_data
    end

    # Returns all pages as nested json object for tree views
    #
    # Pass a page_id param to only load tree for this page
    #
    # Pass elements=true param to include elements for pages
    #
    def nested
      @page = Page.find_by(id: params[:page_id]) || Language.current_root_page

      render json: PageTreeSerializer.new(@page,
        ability: current_ability,
        user: current_alchemy_user,
        elements: params[:elements],
        full: true)
    end

    # Returns a json object for page
    #
    # You can either load the page via id or its urlname
    #
    def show
      authorize! :show, @page
      respond_with @page
    end

    def move
      @page = Page.find(params[:id])
      authorize! :update, @page
      target_parent_page = Page.find(params[:target_parent_id])
      @page.move_to_child_with_index(target_parent_page, params[:new_position])
      render json: @page, serializer: PageSerializer
    end

    private

    def load_page
      @page = load_page_by_id || load_page_by_urlname || raise(ActiveRecord::RecordNotFound)
    end

    def load_page_by_id
      # The route param is called :urlname although it might be an integer
      Page.where(id: params[:urlname]).includes(page_includes).first
    end

    def load_page_by_urlname
      return unless Language.current

      Language.current.pages.where(
        urlname: params[:urlname],
        language_code: params[:locale] || Language.current.code,
      ).includes(page_includes).first
    end

    def meta_data
      {
        total_count: total_count_value,
        per_page: per_page_value,
        page: page_value,
      }
    end

    def total_count_value
      params[:page] ? @pages.total_count : @pages.size
    end

    def per_page_value
      if params[:page]
        (params[:per_page] || Kaminari.config.default_per_page).to_i
      else
        @pages.size
      end
    end

    def page_value
      params[:page] ? params[:page].to_i : nil
    end

    def page_includes
      [
        :tags,
        {
          language: :site,
          elements: [
            {
              nested_elements: [
                {
                  contents: :essence,
                },
                :tags,
              ],
            },
            {
              contents: :essence,
            },
            :tags,
          ],
        },
      ]
    end
  end
end
