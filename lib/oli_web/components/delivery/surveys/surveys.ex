defmodule OliWeb.Components.Delivery.Surveys do
  use OliWeb, :live_component

  import Ecto.Query
  alias Oli.Accounts.User

  alias Oli.Analytics.Summary.{
    ResourcePartResponse,
    ResourceSummary,
    ResponseSummary,
    StudentResponse
  }

  alias Oli.Repo

  alias Oli.Publishing.DeliveryResolver

  alias OliWeb.Delivery.Surveys.{
    SurveysAssessmentsTableModel
  }

  alias OliWeb.Common.Params
  alias Phoenix.LiveView.JS
  alias OliWeb.Common.{PagedTable, SearchInput}
  alias OliWeb.Router.Helpers, as: Routes
  alias OliWeb.Common.Table.SortableTableModel
  alias Oli.Delivery.Attempts.Core
  alias OliWeb.ManualGrading.RenderedActivity
  alias Oli.Repo

  alias Oli.Delivery.Attempts.Core.{
    ResourceAccess,
    ResourceAttempt,
    ActivityAttempt
  }

  alias Oli.Delivery.Sections.Section

  alias Oli.Resources.Revision

  @default_params %{
    offset: 0,
    limit: 20,
    sort_order: :asc,
    sort_by: :title,
    text_search: nil
  }

  def mount(socket) do
    {:ok,
     assign(socket,
       scripts_loaded: false,
       table_model: nil,
       current_assessment: nil,
       activities: nil
     )}
  end

  def update(assigns, socket) do
    params = decode_params(assigns.params)

    {total_count, rows} = apply_filters(assigns.assessments, params)

    {:ok, table_model} =
      SurveysAssessmentsTableModel.new(rows, assigns.ctx, socket.assigns.myself)

    table_model =
      Map.merge(table_model, %{
        rows: rows,
        sort_order: params.sort_order
      })
      |> SortableTableModel.update_sort_params(params.sort_by)

    {:ok,
     assign(socket,
       params: params,
       section: assigns.section,
       view: assigns.view,
       ctx: assigns.ctx,
       assessments: assigns.assessments,
       students: assigns.students,
       student_ids: Enum.map(assigns.students, & &1.id),
       scripts: assigns.scripts,
       activity_types_map: assigns.activity_types_map,
       preview_rendered: nil,
       table_model: table_model,
       total_count: total_count
     )}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.loader if={!@table_model} />
      <div :if={@table_model} class="bg-white shadow-sm dark:bg-gray-800 dark:text-white">
        <div class="flex flex-col space-y-4 lg:space-y-0 lg:flex-row lg:justify-between px-9 lg:items-center">
          <h4 class="torus-h4 whitespace-nowrap">Surveys</h4>

          <div class="flex flex-col">
            <form
              for="search"
              phx-target={@myself}
              phx-change="search_assessment"
              class="pb-6 lg:ml-auto lg:pt-7"
            >
              <SearchInput.render
                id="assessments_search_input"
                name="assessment_name"
                text={@params.text_search}
              />
            </form>
          </div>
        </div>

        <PagedTable.render
          table_model={@table_model}
          total_count={@total_count}
          offset={@params.offset}
          limit={@params.limit}
          page_change={JS.push("paged_table_page_change", target: @myself)}
          selection_change={JS.push("paged_table_selection_change", target: @myself)}
          sort={JS.push("paged_table_sort", target: @myself)}
          additional_table_class="instructor_dashboard_table"
          allow_selection={true}
          show_bottom_paging={false}
          limit_change={JS.push("paged_table_limit_change", target: @myself)}
          show_limit_change={true}
        />
        <%= unless is_nil(@activities) do %>
          <%= if @activities == [] do %>
            <div class="bg-white dark:bg-gray-800 dark:text-white shadow-sm px-10 my-5 mx-10">
              <p class="py-5">No attempt registered for this question</p>
            </div>
          <% else %>
            <div class="mt-9">
              <div :for={activity <- @activities} class="px-10">
                <div class="flex flex-col bg-white dark:bg-gray-800 dark:text-white w-min whitespace-nowrap rounded-t-md block font-medium text-sm leading-tight uppercase border-x-1 border-t-1 border-b-0 border-gray-300 px-6 py-4 my-4 gap-y-2">
                  <div role="activity_title"><%= activity.title %> - Question details</div>
                  <div
                    :if={@current_assessment != nil and @activities not in [nil, []]}
                    id="student_attempts_summary"
                    class="flex flex-row gap-x-2 lowercase"
                  >
                    <span class="text-xs">
                      <%= if activity.students_with_attempts_count == 0 do %>
                        No student has completed any attempts.
                      <% else %>
                        <%= ~s{#{activity.students_with_attempts_count} #{Gettext.ngettext(OliWeb.Gettext, "student has", "students have", activity.students_with_attempts_count)} completed #{activity.total_attempts_count} #{Gettext.ngettext(OliWeb.Gettext, "attempt", "attempts", activity.total_attempts_count)}.} %>
                      <% end %>
                    </span>
                    <div
                      :if={activity.students_with_attempts_count < Enum.count(@students)}
                      class="flex flex-col gap-x-2 items-center"
                    >
                      <span class="text-xs">
                        <%= ~s{#{Enum.count(activity.student_emails_without_attempts)} #{Gettext.ngettext(OliWeb.Gettext,
                        "student has",
                        "students have",
                        Enum.count(activity.student_emails_without_attempts))} not completed any attempt.} %>
                      </span>
                      <input
                        type="text"
                        id="email_inputs"
                        class="form-control hidden"
                        value={Enum.join(activity.student_emails_without_attempts, "; ")}
                        readonly
                      />
                      <button
                        id="copy_emails_button"
                        class="text-xs text-primary underline ml-auto"
                        phx-hook="CopyListener"
                        data-clipboard-target="#email_inputs"
                      >
                        <i class="fa-solid fa-copy mr-2" /><%= Gettext.ngettext(
                          OliWeb.Gettext,
                          "Copy email address",
                          "Copy email addresses",
                          Enum.count(activity.student_emails_without_attempts)
                        ) %>
                      </button>
                    </div>
                  </div>
                </div>
                <div
                  class="bg-white dark:bg-gray-800 dark:text-white shadow-sm px-6 -mt-5"
                  id="activity_detail"
                  phx-hook="LoadSurveyScripts"
                >
                  <%= if activity.preview_rendered != nil do %>
                    <RenderedActivity.render
                      id={"activity_#{activity.id}"}
                      rendered_activity={activity.preview_rendered}
                    />
                  <% else %>
                    <p class="pt-9 pb-5">No attempt registered for this question</p>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event(
        "paged_table_selection_change",
        %{"id" => survey_id},
        socket
      ) do
    %{
      students: students,
      student_ids: student_ids,
      section: section
    } =
      socket.assigns

    current_assessment = find_current_assessment(socket, survey_id)

    current_activities =
      find_current_activities(current_assessment, section, student_ids, students, socket)

    assign_assessments_activities_table_model(
      socket,
      current_assessment,
      current_activities
    )
  end

  def handle_event(
        "search_assessment",
        %{"assessment_name" => assessment_name},
        socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         route_to(
           socket,
           update_params(socket.assigns.params, %{
             text_search: assessment_name,
             offset: 0
           })
         )
     )}
  end

  def handle_event(
        "paged_table_page_change",
        %{"limit" => limit, "offset" => offset},
        socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         route_to(
           socket,
           update_params(socket.assigns.params, %{limit: limit, offset: offset})
         )
     )}
  end

  def handle_event(
        "paged_table_limit_change",
        params,
        %{assigns: %{params: current_params}} = socket
      ) do
    new_limit = Params.get_int_param(params, "limit", 20)

    new_offset =
      OliWeb.Common.PagingParams.calculate_new_offset(
        current_params.offset,
        new_limit,
        socket.assigns.total_count
      )

    {:noreply,
     push_patch(socket,
       to:
         route_to(
           socket,
           update_params(socket.assigns.params, %{limit: new_limit, offset: new_offset})
         )
     )}
  end

  def handle_event("survey_scripts_loaded", %{"error" => _}, socket) do
    {:noreply, assign(socket, error: true)}
  end

  def handle_event("survey_scripts_loaded", _params, socket) do
    {:noreply, assign(socket, scripts_loaded: true)}
  end

  def handle_event(
        "paged_table_sort",
        %{"sort_by" => sort_by} = _params,
        socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         route_to(
           socket,
           update_params(socket.assigns.params, %{
             sort_by: String.to_existing_atom(sort_by)
           })
         )
     )}
  end

  defp assign_assessments_activities_table_model(
         socket,
         current_assessment,
         current_activities
       ) do
    {:noreply,
     assign(socket,
       current_assessment: current_assessment,
       activities: current_activities
     )
     |> assign_selected_assessment(current_assessment.id)
     |> case do
       %{assigns: %{scripts_loaded: true}} = socket ->
         socket

       socket ->
         push_event(socket, "load_survey_scripts", %{
           script_sources: socket.assigns.scripts
         })
     end}
  end

  # # defp assign_selected_survey(socket, survey_id) do
  #   Map.merge(socket.assigns.table_model, %{
  #     selected: "#{survey_id}"
  #   })
  # end

  defp find_current_activities(current_assessment, section, student_ids, students, socket) do
    get_activities(current_assessment, section, student_ids)
    |> Enum.map(fn activity ->
      Map.put(activity, :preview_rendered, get_preview_rendered(activity, socket))
      |> add_activity_attempts_info(students, student_ids, section)
    end)
  end

  defp find_current_assessment(socket, survey_id) do
    Enum.find(socket.assigns.assessments, fn assessment ->
      assessment.id == String.to_integer(survey_id)
    end)
  end

  defp assign_selected_assessment(socket, selected_assessment_id)
       when selected_assessment_id in ["", nil] do
    case socket.assigns.table_model.rows do
      [] ->
        socket

      rows ->
        assign_selected_assessment(socket, hd(rows).resource_id)
    end
  end

  defp assign_selected_assessment(socket, selected_assessment_id) do
    table_model =
      Map.merge(socket.assigns.table_model, %{
        selected: "#{selected_assessment_id}"
      })

    assign(socket, table_model: table_model)
  end

  defp add_activity_attempts_info(activity, students, student_ids, section) do
    students_with_attempts =
      DeliveryResolver.students_with_attempts_for_page(
        activity,
        section,
        student_ids
      )

    student_emails_without_attempts =
      Enum.reduce(students, [], fn s, acc ->
        if s.id in students_with_attempts do
          acc
        else
          [s.email | acc]
        end
      end)

    activity
    |> Map.put(:students_with_attempts_count, Enum.count(students_with_attempts))
    |> Map.put(:student_emails_without_attempts, student_emails_without_attempts)
    |> Map.put(:total_attempts_count, count_attempts(activity, section, student_ids) || 0)
  end

  defp get_preview_rendered(activity, socket) do
    case get_activity_details(
           activity,
           socket.assigns.section,
           socket.assigns.activity_types_map
         ) do
      nil ->
        socket

      activity_attempt ->
        part_attempts = Core.get_latest_part_attempts(activity_attempt.attempt_guid)

        rendering_context =
          OliWeb.ManualGrading.Rendering.create_rendering_context(
            activity_attempt,
            part_attempts,
            socket.assigns.activity_types_map,
            socket.assigns.section
          )
          |> Map.merge(%{is_liveview: true})

        OliWeb.ManualGrading.Rendering.render(
          rendering_context,
          :instructor_preview
        )
    end
  end

  defp apply_filters(assessments, params) do
    assessments =
      assessments
      |> maybe_filter_by_text(params.text_search)
      |> sort_by(params.sort_by, params.sort_order)

    {length(assessments), assessments |> Enum.drop(params.offset) |> Enum.take(params.limit)}
  end

  defp maybe_filter_by_text(assessments, nil), do: assessments
  defp maybe_filter_by_text(assessments, ""), do: assessments

  defp maybe_filter_by_text(assessments, text_search) do
    Enum.filter(assessments, fn assessment ->
      String.contains?(
        String.downcase(assessment.title),
        String.downcase(text_search)
      )
    end)
  end

  defp sort_by(assessments, sort_by, sort_order) do
    case sort_by do
      :due_date ->
        Enum.sort_by(
          assessments,
          fn a ->
            if a.scheduling_type != :due_by, do: 0, else: Map.get(a, :due_date)
          end,
          sort_order
        )

      sb when sb in [:avg_score, :students_completion, :total_attempts] ->
        Enum.sort_by(assessments, fn a -> Map.get(a, sb) || -1 end, sort_order)

      :title ->
        Enum.sort_by(
          assessments,
          fn a -> Map.get(a, :title) |> String.downcase() end,
          sort_order
        )
    end
  end

  defp decode_params(params) do
    %{
      offset: Params.get_int_param(params, "offset", @default_params.offset),
      limit: Params.get_int_param(params, "limit", @default_params.limit),
      sort_order:
        Params.get_atom_param(
          params,
          "sort_order",
          [:asc, :desc],
          @default_params.sort_order
        ),
      sort_by:
        Params.get_atom_param(
          params,
          "sort_by",
          [
            :title,
            :due_date,
            :avg_score,
            :total_attempts,
            :students_completion
          ],
          @default_params.sort_by
        ),
      text_search: Params.get_param(params, "text_search", @default_params.text_search),
      assessment_id: Params.get_int_param(params, "assessment_id", nil),
      selected_activity: Params.get_param(params, "selected_activity", nil)
    }
  end

  defp update_params(
         %{sort_by: current_sort_by, sort_order: current_sort_order} = params,
         %{
           sort_by: new_sort_by
         }
       )
       when current_sort_by == new_sort_by do
    toggled_sort_order = if current_sort_order == :asc, do: :desc, else: :asc
    update_params(params, %{sort_order: toggled_sort_order})
  end

  defp update_params(params, new_param) do
    Map.merge(params, new_param)
  end

  defp route_to(socket, params)
       when not is_nil(socket.assigns.params.assessment_id) do
    Routes.live_path(
      socket,
      OliWeb.Delivery.InstructorDashboard.InstructorDashboardLive,
      socket.assigns.section.slug,
      socket.assigns.view,
      :surveys,
      socket.assigns.params.assessment_id,
      params
    )
  end

  defp route_to(socket, params) do
    Routes.live_path(
      socket,
      OliWeb.Delivery.InstructorDashboard.InstructorDashboardLive,
      socket.assigns.section.slug,
      socket.assigns.view,
      :surveys,
      params
    )
  end

  defp count_attempts(
         current_activity,
         %Section{analytics_version: :v2, id: section_id},
         student_ids
       ) do
    page_type_id = Oli.Resources.ResourceType.get_id_by_type("activity")

    from(rs in ResourceSummary,
      where:
        rs.section_id == ^section_id and rs.resource_id == ^current_activity.resource_id and
          rs.user_id in ^student_ids and rs.project_id == -1 and rs.publication_id == -1 and
          rs.resource_type_id == ^page_type_id,
      select: sum(rs.num_attempts)
    )
    |> Repo.one()
  end

  defp count_attempts(current_activity, section, student_ids) do
    from(ra in ResourceAttempt,
      join: access in ResourceAccess,
      on: access.id == ra.resource_access_id,
      where:
        ra.lifecycle_state == :evaluated and access.section_id == ^section.id and
          access.resource_id == ^current_activity.resource_id and access.user_id in ^student_ids,
      select: count(ra.id)
    )
    |> Repo.one()
  end

  defp get_activities(current_assessment, section, student_ids) do
    activities =
      from(aa in ActivityAttempt,
        join: res_attempt in ResourceAttempt,
        on: aa.resource_attempt_id == res_attempt.id,
        where: aa.lifecycle_state == :evaluated,
        join: res_access in ResourceAccess,
        on: res_attempt.resource_access_id == res_access.id,
        where:
          res_access.section_id == ^section.id and
            res_access.resource_id == ^current_assessment.resource_id and
            res_access.user_id in ^student_ids and not is_nil(aa.survey_id),
        join: rev in Revision,
        on: aa.revision_id == rev.id,
        group_by: [rev.resource_id, rev.id],
        select:
          {rev, count(aa.id),
           sum(aa.score) /
             fragment("CASE WHEN SUM(?) = 0.0 THEN 1.0 ELSE SUM(?) END", aa.out_of, aa.out_of)}
      )
      |> Repo.all()
      |> Enum.map(fn {rev, total_attempts, avg_score} ->
        Map.merge(rev, %{total_attempts: total_attempts, avg_score: avg_score})
      end)

    objectives_mapper =
      Enum.reduce(activities, [], fn activity, acc ->
        (Map.values(activity.objectives) |> List.flatten()) ++ acc
      end)
      |> Enum.uniq()
      |> DeliveryResolver.objectives_by_resource_ids(section.slug)
      |> Enum.map(fn objective -> {objective.resource_id, objective} end)
      |> Enum.into(%{})

    activities
    |> Enum.map(fn activity ->
      case Map.values(activity.objectives) |> List.flatten() do
        [] ->
          Map.put(activity, :objectives, [])

        objective_ids ->
          Map.put(
            activity,
            :objectives,
            Enum.reduce(objective_ids, MapSet.new(), fn id, activity_objectives ->
              MapSet.put(activity_objectives, Map.get(objectives_mapper, id))
            end)
            |> MapSet.to_list()
          )
      end
    end)
  end

  defp get_activity_details(selected_activity, section, activity_types_map) do
    query =
      ActivityAttempt
      |> join(:left, [aa], resource_attempt in ResourceAttempt,
        on: aa.resource_attempt_id == resource_attempt.id
      )
      |> join(:left, [_, resource_attempt], ra in ResourceAccess,
        on: resource_attempt.resource_access_id == ra.id
      )
      |> join(:left, [_, _, ra], a in assoc(ra, :user))
      |> join(:left, [aa, _, _, _], activity_revision in Revision,
        on: activity_revision.id == aa.revision_id
      )
      |> join(:left, [_, resource_attempt, _, _, _], resource_revision in Revision,
        on: resource_revision.id == resource_attempt.revision_id
      )
      |> where(
        [aa, _resource_attempt, resource_access, _u, activity_revision, _resource_revision],
        resource_access.section_id == ^section.id and
          activity_revision.resource_id == ^selected_activity.resource_id
      )
      |> order_by([aa, _, _, _, _, _], desc: aa.inserted_at)
      |> limit(1)
      |> Ecto.Query.select([aa, _, _, _, _, _], aa)
      |> select_merge(
        [aa, resource_attempt, resource_access, user, activity_revision, resource_revision],
        %{
          activity_type_id: activity_revision.activity_type_id,
          activity_title: activity_revision.title,
          page_title: resource_revision.title,
          page_id: resource_revision.resource_id,
          resource_attempt_number: resource_attempt.attempt_number,
          graded: resource_revision.graded,
          user: user,
          revision: activity_revision,
          resource_attempt_guid: resource_attempt.attempt_guid,
          resource_access_id: resource_access.id
        }
      )

    multiple_choice_type_id =
      Enum.find(activity_types_map, fn {_k, v} -> v.title == "Multiple Choice" end)
      |> elem(0)

    single_response_type_id =
      Enum.find(activity_types_map, fn {_k, v} -> v.title == "Single Response" end)
      |> elem(0)

    multi_input_type_id =
      Enum.find(activity_types_map, fn {_k, v} -> v.title == "Multi Input" end)
      |> elem(0)

    likert_type_id =
      Enum.find(activity_types_map, fn {_k, v} -> v.title == "Likert" end)
      |> elem(0)

    case Repo.one(query) do
      nil ->
        nil

      %{activity_type_id: activity_type_id} = activity_attempt
      when activity_type_id == multiple_choice_type_id ->
        add_choices_frequencies(activity_attempt, section)

      %{activity_type_id: activity_type_id} = activity_attempt
      when activity_type_id == single_response_type_id ->
        add_single_response_details(activity_attempt, section)

      %{activity_type_id: activity_type_id} = activity_attempt
      when activity_type_id == multi_input_type_id ->
        add_multi_input_details(activity_attempt, section)

      %{activity_type_id: activity_type_id} = activity_attempt
      when activity_type_id == likert_type_id ->
        add_likert_details(activity_attempt, section)

      activity_attempt ->
        activity_attempt
    end
  end

  defp add_single_response_details(activity_attempt, %Section{analytics_version: :v1}),
    do: activity_attempt

  defp add_single_response_details(activity_attempt, section) do
    responses =
      from(rs in ResponseSummary,
        where:
          rs.section_id == ^section.id and rs.activity_id == ^activity_attempt.resource_id and
            rs.page_id == ^activity_attempt.page_id and
            rs.publication_id == -1 and rs.project_id == -1,
        join: rpp in ResourcePartResponse,
        on: rs.resource_part_response_id == rpp.id,
        join: sr in StudentResponse,
        on:
          rs.section_id == sr.section_id and rs.page_id == sr.page_id and
            rs.resource_part_response_id == sr.resource_part_response_id,
        join: u in User,
        on: sr.user_id == u.id,
        select: %{text: rpp.response, user: u}
      )
      |> Repo.all()
      |> Enum.map(fn response ->
        %{text: response.text, user_name: OliWeb.Common.Utils.name(response.user)}
      end)

    update_in(
      activity_attempt,
      [Access.key!(:revision), Access.key!(:content)],
      &Map.put(&1, "responses", responses)
    )
  end

  defp add_choices_frequencies(activity_attempt, %Section{analytics_version: :v1}),
    do: activity_attempt

  defp add_choices_frequencies(activity_attempt, section) do
    choice_frequency_mapper =
      from(rs in ResponseSummary,
        where:
          rs.section_id == ^section.id and
            rs.project_id == -1 and
            rs.publication_id == -1 and
            rs.page_id == ^activity_attempt.page_id and
            rs.activity_id == ^activity_attempt.resource_id,
        join: rpp in assoc(rs, :resource_part_response),
        preload: [resource_part_response: rpp],
        select: rs
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn response_summary, acc ->
        Map.put(acc, response_summary.resource_part_response.response, response_summary.count)
      end)

    choices =
      activity_attempt.transformed_model["choices"]
      |> Enum.map(fn choice ->
        Map.merge(choice, %{
          "frequency" => Map.get(choice_frequency_mapper, choice["id"]) || 0
        })
      end)
      |> Kernel.++(
        if Map.has_key?(choice_frequency_mapper, "") do
          [
            %{
              "content" => [
                %{
                  "children" => [
                    %{
                      "text" =>
                        "Blank attempt (user submitted assessment without selecting any choice for this activity)"
                    }
                  ],
                  "type" => "p"
                }
              ],
              "frequency" => Map.get(choice_frequency_mapper, "")
            }
          ]
        else
          []
        end
      )

    update_in(
      activity_attempt,
      [Access.key!(:transformed_model)],
      &Map.put(&1, "choices", choices)
    )
  end

  defp add_multi_input_details(activity_attempt, %Section{analytics_version: :v1}),
    do: activity_attempt

  defp add_multi_input_details(activity_attempt, section) do
    input_type = Enum.at(activity_attempt.transformed_model["inputs"], 0)["inputType"]

    case input_type do
      response when response in ["numeric", "text"] ->
        responses =
          from(rs in ResponseSummary,
            where:
              rs.section_id == ^section.id and rs.activity_id == ^activity_attempt.resource_id and
                rs.page_id == ^activity_attempt.page_id and
                rs.publication_id == -1 and rs.project_id == -1,
            join: rpp in ResourcePartResponse,
            on: rs.resource_part_response_id == rpp.id,
            join: sr in StudentResponse,
            on:
              rs.section_id == sr.section_id and rs.page_id == sr.page_id and
                rs.resource_part_response_id == sr.resource_part_response_id,
            join: u in User,
            on: sr.user_id == u.id,
            select: %{text: rpp.response, user: u}
          )
          |> Repo.all()
          |> Enum.map(fn response ->
            %{text: response.text, user_name: OliWeb.Common.Utils.name(response.user)}
          end)

        update_in(
          activity_attempt,
          [Access.key!(:transformed_model), Access.key!("authoring")],
          &Map.put(&1, "responses", responses)
        )

      response when response == "dropdown" ->
        choice_frequency_mapper =
          from(rs in ResponseSummary,
            where:
              rs.section_id == ^section.id and
                rs.project_id == -1 and
                rs.publication_id == -1 and
                rs.page_id == ^activity_attempt.page_id and
                rs.activity_id == ^activity_attempt.resource_id,
            join: rpp in assoc(rs, :resource_part_response),
            preload: [resource_part_response: rpp],
            select: rs
          )
          |> Repo.all()
          |> Enum.reduce(%{}, fn response_summary, acc ->
            Map.put(acc, response_summary.resource_part_response.response, response_summary.count)
          end)

        choices =
          activity_attempt.transformed_model["choices"]
          |> Enum.map(fn choice ->
            Map.merge(choice, %{
              "frequency" => Map.get(choice_frequency_mapper, choice["id"]) || 0
            })
          end)
          |> Kernel.++(
            if Map.has_key?(choice_frequency_mapper, "") do
              [
                %{
                  "content" => [
                    %{
                      "children" => [
                        %{
                          "text" =>
                            "Blank attempt (user submitted assessment without selecting any choice for this activity)"
                        }
                      ],
                      "type" => "p"
                    }
                  ],
                  "editor" => "slate",
                  "frequency" => Map.get(choice_frequency_mapper, ""),
                  "id" => "0",
                  "textDirection" => "ltr"
                }
              ]
            else
              []
            end
          )

        update_in(
          activity_attempt,
          [Access.key!(:transformed_model)],
          &Map.put(&1, "choices", choices)
        )
        |> update_in(
          [
            Access.key!(:transformed_model),
            Access.key!("inputs"),
            Access.at!(0),
            Access.key!("choiceIds")
          ],
          &List.insert_at(&1, -1, "0")
        )
    end
  end

  defp add_likert_details(activity_attempt, %Section{analytics_version: :v1}),
    do: activity_attempt

  defp add_likert_details(activity_attempt, section) do
    choice_frequency_mapper =
      from(rs in ResponseSummary,
        where:
          rs.section_id == ^section.id and
            rs.project_id == -1 and
            rs.publication_id == -1 and
            rs.page_id == ^activity_attempt.page_id and
            rs.activity_id == ^activity_attempt.resource_id,
        join: rpp in assoc(rs, :resource_part_response),
        preload: [resource_part_response: rpp],
        select: rs
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn response_summary, acc ->
        Map.put(acc, response_summary.resource_part_response.response, response_summary.count)
      end)

    choices =
      activity_attempt.revision.content["choices"]
      |> Enum.map(fn choice ->
        Map.merge(choice, %{
          "frequency" => Map.get(choice_frequency_mapper, choice["id"]) || 0
        })
      end)
      |> Kernel.++(
        if Map.has_key?(choice_frequency_mapper, "") do
          [
            %{
              "content" => [
                %{
                  "children" => [
                    %{
                      "text" =>
                        "Blank attempt (user submitted assessment without selecting any choice for this activity)"
                    }
                  ],
                  "type" => "p"
                }
              ],
              "editor" => "slate",
              "frequency" => Map.get(choice_frequency_mapper, ""),
              "id" => "0",
              "textDirection" => "ltr"
            }
          ]
        else
          []
        end
      )

    update_in(
      activity_attempt,
      [Access.key!(:revision), Access.key!(:content)],
      &Map.put(&1, "choices", choices)
    )
    |> update_in(
      [
        Access.key!(:revision),
        Access.key!(:content)
      ],
      &Map.put(&1, "activityTitle", activity_attempt.revision.title)
    )
  end
end
