defmodule OliWeb.CollaborationLive.IndexView do
  use OliWeb, :live_view
  use OliWeb.Common.SortableTable.TableHandlers

  alias Oli.Resources.Collaboration
  alias OliWeb.Admin.AdminView
  alias OliWeb.Common.{Breadcrumb, Filter, Listing, SessionContext}
  alias OliWeb.CollaborationLive.{AdminTableModel, InstructorTableModel}
  alias OliWeb.Router.Helpers, as: Routes
  alias alias OliWeb.Sections.Mount

  @title "Collaborative Spaces"

  @table_filter_fn &__MODULE__.filter_rows/3
  @table_push_patch_path &__MODULE__.live_path/2

  def filter_rows(socket, query, _filter) do
    query_str = String.downcase(query)

    Enum.filter(socket.assigns.collab_spaces, fn cs ->
      String.contains?(String.downcase(cs.page.title), query_str) or
        (socket.assigns.live_action == :admin and
           String.contains?(String.downcase(cs.project.title), query_str))
    end)
  end

  def live_path(%{assigns: %{live_action: :admin}} = socket, params),
    do: Routes.collab_spaces_index_path(socket, :admin, params)

  def live_path(
        %{assigns: %{live_action: :instructor, section_slug: section_slug}} = socket,
        params
      ),
      do: Routes.collab_spaces_index_path(socket, :instructor, section_slug, params)

  def breadcrumb(:admin, _) do
    AdminView.breadcrumb() ++
      [
        Breadcrumb.new(%{
          full_title: @title,
          link: Routes.collab_spaces_index_path(OliWeb.Endpoint, :admin)
        })
      ]
  end

  def breadcrumb(:instructor, section_slug) do
    OliWeb.Sections.OverviewView.set_breadcrumbs(:instructor, %{slug: section_slug}) ++
      [
        Breadcrumb.new(%{
          full_title: @title,
          link: Routes.collab_spaces_index_path(OliWeb.Endpoint, :instructor, section_slug)
        })
      ]
  end

  def mount(params, session, socket) do
    live_action = socket.assigns.live_action
    ctx = SessionContext.init(socket, session)
    section_slug = params["section_slug"]

    do_mount = fn ->
      {collab_spaces, table_model} =
        get_collab_spaces_and_table_model(live_action, ctx, section_slug)

      {:ok,
       assign(socket,
         breadcrumbs: breadcrumb(live_action, section_slug),
         section_slug: section_slug,
         collab_spaces: collab_spaces,
         table_model: table_model,
         total_count: length(collab_spaces),
         limit: 20,
         offset: 0,
         query: ""
       )}
    end

    case live_action do
      :instructor ->
        case Mount.for(section_slug, session) do
          {:error, e} ->
            Mount.handle_error(socket, {:error, e})

          {_type, _user, _section} ->
            do_mount.()
        end

      :admin ->
        do_mount.()
    end
  end

  def render(assigns) do
    ~H"""
    <div class="d-flex p-3 justify-content-between">
      <Filter.render change="change_search" reset="reset_search" apply="apply_search" query={@query} />
    </div>

    <div id="collaborative-spaces-table" class="p-4">
      <Listing.render
        filter={@query}
        table_model={@table_model}
        total_count={@total_count}
        offset={@offset}
        limit={@limit}
        sort="sort"
        page_change="page_change"
        show_bottom_paging={false}
      />
    </div>
    """
  end

  defp get_collab_spaces_and_table_model(:admin, ctx, _) do
    collab_spaces = Collaboration.list_collaborative_spaces()
    {:ok, table_model} = AdminTableModel.new(collab_spaces, ctx)

    {collab_spaces, table_model}
  end

  defp get_collab_spaces_and_table_model(:instructor, ctx, section_slug) do
    {_, collab_spaces} = Collaboration.list_collaborative_spaces_in_section(section_slug)
    {:ok, table_model} = InstructorTableModel.new(collab_spaces, ctx)

    {collab_spaces, table_model}
  end
end
