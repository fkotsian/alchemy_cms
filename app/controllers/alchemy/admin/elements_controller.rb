# frozen_string_literal: true

module Alchemy
  module Admin
    class ElementsController < Alchemy::Admin::BaseController
      before_action :load_element, only: [:update, :destroy, :fold, :publish]
      authorize_resource class: Alchemy::Element

      def index
        @page_version = PageVersion.find(params[:page_version_id])
        @page = @page_version.page
        elements = @page_version.elements.order(:position).includes(*element_includes)
        @elements = elements.not_nested.unfixed
        @fixed_elements = elements.not_nested.fixed
        load_clipboard_items
      end

      def new
        @page_version = PageVersion.find(params[:page_version_id])
        @page = @page_version.page
        @parent_element = Element.find_by(id: params[:parent_element_id])
        @elements = @page.available_elements_within_current_scope(@parent_element)
        @element = @page_version.elements.build
        load_clipboard_items
      end

      # Creates a element as discribed in config/alchemy/elements.yml on page via AJAX.
      def create
        @page_version = PageVersion.find(params[:element][:page_version_id])
        @page = @page_version.page
        Element.transaction do
          if @paste_from_clipboard = params[:paste_from_clipboard].present?
            @element = paste_element_from_clipboard
          else
            @element = Element.new(create_element_params)
          end
          if @page.definition["insert_elements_at"] == "top"
            @insert_at_top = true
            @element.position = 1
          end
        end
        if @element.save
          render :create
        else
          @element.page_version = @page_version
          @elements = @page.available_element_definitions
          load_clipboard_items
          render :new
        end
      end

      # Updates the element.
      #
      # And update all contents in the elements by calling update_contents.
      #
      def update
        @page = @element.page

        if element_params.key?(:ingredients_attributes)
          update_element_with_ingredients
        else
          update_element_with_contents
        end
      end

      def destroy
        @richtext_ids = @element.richtext_contents_ids + @element.richtext_ingredients_ids
        @element.destroy
        @notice = Alchemy.t("Successfully deleted element") % { element: @element.display_name }
      end

      def publish
        @element.update(public: !@element.public?)
      end

      def order
        @parent_element = Element.find_by(id: params[:parent_element_id])
        Element.transaction do
          params.fetch(:element_ids, []).each.with_index(1) do |element_id, position|
            # We need to set the parent_element_id, because we might have dragged the
            # element over from another nestable element
            Element.find_by(id: element_id).update_columns(
              parent_element_id: params[:parent_element_id],
              position: position,
            )
          end
          # Need to manually touch the parent because Rails does not do it
          # with the update_columns above
          @parent_element&.touch
        end
      end

      # Toggle fodls the element and persists the state in the db
      #
      # Ingredient validations might make the element invalid.
      # In this case we are just toggling a UI state and do not care about the validations.
      def fold
        @page = @element.page
        @element.folded = !@element.folded
        @element.save(validate: false)
      end

      private

      def element_includes
        [
          {
            contents: :essence,
            ingredients: :related_object,
          },
          :tags,
          {
            all_nested_elements: [
              {
                contents: :essence,
                ingredients: :related_object,
              },
              :tags,
            ],
          },
        ]
      end

      def load_element
        @element = Element.find(params[:id])
      end

      def load_clipboard_items
        @clipboard = get_clipboard("elements")
        @clipboard_items = Element.all_from_clipboard_for_page(@clipboard, @page)
      end

      def element_from_clipboard
        @element_from_clipboard ||= begin
          @clipboard = get_clipboard("elements")
          @clipboard.detect { |item| item["id"].to_i == params[:paste_from_clipboard].to_i }
        end
      end

      def paste_element_from_clipboard
        @source_element = Element.find(element_from_clipboard["id"])
        element = Element.copy(
          @source_element,
          {
            parent_element_id: create_element_params[:parent_element_id],
            page_version_id: @page_version.id,
          }
        )
        if element_from_clipboard["action"] == "cut"
          @cut_element_id = @source_element.id
          @clipboard.delete_if { |item| item["id"] == @source_element.id.to_s }
          @source_element.destroy
        end
        element
      end

      def contents_params
        params.fetch(:contents, {}).permit!
      end

      def element_params
        params.fetch(:element, {}).permit(:tag_list, ingredients_attributes: {})
      end

      def create_element_params
        params.require(:element).permit(:name, :page_version_id, :parent_element_id)
      end

      def update_element_with_ingredients
        if @element.update(element_params)
          @element_validated = true
        else
          element_update_error
          @error_messages = @element.ingredient_error_messages
        end
      end

      def update_element_with_contents
        if @element.update_contents(contents_params)
          @element_validated = @element.update(element_params)
        else
          element_update_error
          @error_messages = @element.essence_error_messages
        end
      end

      def element_update_error
        @element_validated = false
        @notice = Alchemy.t("Validation failed")
        @error_message = "<h2>#{@notice}</h2><p>#{Alchemy.t(:content_validations_headline)}</p>".html_safe
      end
    end
  end
end
