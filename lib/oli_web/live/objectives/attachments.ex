defmodule OliWeb.Objectives.Attachments do

  use Phoenix.LiveComponent

  defp locked_by_email(locked_by, id) do
    case Map.get(locked_by, id) do
      nil -> ""
      m -> if m.locked_by_id != nil do m.locked_by_id else "" end
    end
  end

  defp get_type(r) do
    if Map.get(r, :part) == "attached" do "Page" else "Activity" end
  end

  def render(%{attachment_summary: %{attachments: {pages, activities}, locked_by: locked_by}} = assigns) do
    is_locked? = fn id -> Map.get(locked_by, id) != nil end

    all = pages ++ activities

    resources_locked = Enum.filter(all, fn r -> is_locked?.(r.resource_id) end)
    resources_not_locked = Enum.filter(all, fn r -> !is_locked?.(r.resource_id) end)

    ~L"""
    <div>

      <%= if length(resources_not_locked) == 0 and length(resources_locked) == 0 do %>
        <p class="mb-4">Are you sure you wish to delete this objective?</p>
      <% end %>

      <%= if length(resources_not_locked) > 0 do %>
        <p class="mb-4">Proceeding will automatically remove this objective from the following resources:</p>

        <table class="table table-sm table-bordered">
          <thead>
            <tr><th>Resource</th><th>Title</th></tr>
          </thead>
          <tbody>
          <%= for r <- resources_not_locked do %>
            <tr><td><%= get_type(r) %></td><td><%= r.title %></td></tr>
          <% end %>
          </tbody>
        </table>
      <% end %>

      <%= if length(resources_locked) > 0 do %>
        <p class="mb-4">Deleting this objective is blocked because the following resources that have this objective
        attached to it are currently being edited.</p>

        <table class="table table-sm table-bordered">
          <thead>
            <tr><th>Resource</th><th>Title</th><th>Edited By</th></tr>
          </thead>
          <tbody>
          <%= for r <- resources_locked do %>
            <tr><td><%= get_type(r) %></td><td><%= r.title %></td><td><%= locked_by_email(locked_by, r.resource_id) %></td></tr>
          <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

end
