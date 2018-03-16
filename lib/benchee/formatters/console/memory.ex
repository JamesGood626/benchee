defmodule Benchee.Formatters.Console.Memory do
  @moduledoc """
  This deals with just the formatting of the run time results. They are similar
  to the way the memory results are formatted, but different enough to where the
  abstractions start to break down pretty significantly, so I wanted to extract
  these two things into separate modules to avoid confusion.
  """

  alias Benchee.{
    Statistics,
    Benchmark.Scenario,
    Conversion,
    Conversion.Unit,
    Formatters.Console.Helpers
  }

  @type unit_per_statistic :: %{atom => Unit.t()}

  # Length of column header
  @average_width 15
  @deviation_width 11
  @median_width 15
  @percentile_width 15

  @doc """
  Formats the memory statistics to a report suitable for output on the CLI. If
  all memory measurements are the same and we have a standard deviation of 0.0
  for each scenario, we don't show the statistics and report just on the single
  measured memory usage.
  """
  @spec format_scenarios([Scenario.t()], map) :: [String.t(), ...]
  def format_scenarios(scenarios, config) do
    %{unit_scaling: scaling_strategy} = config
    units = Conversion.units(scenarios, scaling_strategy)
    label_width = Helpers.label_width(scenarios)
    hide_statistics = all_have_deviation_of_0?(scenarios)

    List.flatten([
      "\nMemory usage statistics:\n",
      column_descriptors(label_width, hide_statistics),
      scenario_reports(scenarios, units, label_width, hide_statistics),
      comparison_report(scenarios, units, label_width, config, hide_statistics)
    ])
  end

  defp all_have_deviation_of_0?(scenarios) do
    Enum.all?(scenarios, fn scenario ->
      scenario.memory_usage_statistics.std_dev == 0.0
    end)
  end

  defp column_descriptors(label_width, hide_statistics)
  defp column_descriptors(label_width, false) do
    "\n~*s~*s~*s~*s~*s\n"
    |> :io_lib.format([
      -label_width,
      "Name",
      @average_width,
      "average",
      @deviation_width,
      "deviation",
      @median_width,
      "median",
      @percentile_width,
      "99th %"
    ])
    |> to_string
  end

  defp column_descriptors(label_width, true) do
    "\n~*s~*s\n"
    |> :io_lib.format([
      -label_width,
      "Name",
      @average_width,
      "Memory usage"
    ])
    |> to_string
  end

  @spec scenario_reports([Scenario.t()], unit_per_statistic, integer, boolean) :: [String.t()]
  defp scenario_reports(scenarios, units, label_width, hide_statistics)
  defp scenario_reports([scenario | other_scenarios], units, label_width, true) do
    [
      reference_report(scenario, units, label_width),
      comparisons(scenario, units, label_width, other_scenarios),
      "\n**All measurements for memory usage were the same**\n"
    ]
  end

  defp scenario_reports(scenarios, units, label_width, hide_statistics) do
    Enum.map(scenarios, fn scenario ->
      format_scenario(scenario, units, label_width, hide_statistics)
    end)
  end

  @spec format_scenario(Scenario.t(), unit_per_statistic, integer, boolean) :: String.t()
  defp format_scenario(scenario, %{memory: memory_unit}, label_width, false) do
    %Scenario{
      name: name,
      memory_usage_statistics: %Statistics{
        average: average,
        std_dev_ratio: std_dev_ratio,
        median: median,
        percentiles: %{99 => percentile_99}
      }
    } = scenario

    "~*ts~*ts~*ts~*ts~*ts\n"
    |> :io_lib.format([
      -label_width,
      name,
      @average_width,
      Helpers.duration_output(average, memory_unit),
      @deviation_width,
      Helpers.deviation_output(std_dev_ratio),
      @median_width,
      Helpers.duration_output(median, memory_unit),
      @percentile_width,
      Helpers.duration_output(percentile_99, memory_unit)
    ])
    |> to_string
  end

  defp format_scenario(scenario, %{memory: memory_unit}, label_width, true) do
    %Scenario{
      name: name,
      memory_usage_statistics: %Statistics{
        average: average
      }
    } = scenario

    "~*ts~*ts\n"
    |> :io_lib.format([
      -label_width,
      name,
      @average_width,
      Helpers.duration_output(average, memory_unit)
    ])
    |> to_string
  end

  @spec comparison_report([Scenario.t()], unit_per_statistic, integer, map, boolean) :: [
          String.t()
        ]
  defp comparison_report(scenarios, units, label_width, config, hide_statistics)

  # No need for a comparison when only one benchmark was run
  defp comparison_report([_scenario], _, _, _, _), do: []
  defp comparison_report(_, _, _, %{comparison: false}, _), do: []
  defp comparison_report(_, _, _, _, true), do: []

  defp comparison_report([scenario | other_scenarios], units, label_width, _, _) do
    [
      Helpers.descriptor("Comparison"),
      reference_report(scenario, units, label_width)
      | comparisons(scenario, units, label_width, other_scenarios)
    ]
  end

  defp reference_report(scenario, %{memory: memory_unit}, label_width) do
    %Scenario{
      name: name,
      memory_usage_statistics: %Statistics{median: median}
    } = scenario

    "~*s~*s\n"
    |> :io_lib.format([
      -label_width,
      name,
      @median_width,
      Helpers.duration_output(median, memory_unit)
    ])
    |> to_string
  end

  @spec comparisons(Scenario.t(), unit_per_statistic, integer, [Scenario.t()]) :: [String.t()]
  defp comparisons(scenario, units, label_width, scenarios_to_compare) do
    %Scenario{memory_usage_statistics: reference_stats} = scenario

    Enum.map(scenarios_to_compare, fn scenario = %Scenario{memory_usage_statistics: job_stats} ->
      slower = calculate_slower_value(job_stats.median, reference_stats.median)

      format_comparison(scenario, units, label_width, slower)
    end)
  end

  defp calculate_slower_value(0, _), do: "N/A"
  defp calculate_slower_value(_, 0), do: "N/A"
  defp calculate_slower_value(job_median, reference_median), do: job_median / reference_median

  defp format_comparison(scenario, %{memory: memory_unit}, label_width, "N/A") do
    %Scenario{name: name, memory_usage_statistics: %Statistics{median: median}} = scenario
    median_format = Helpers.duration_output(median, memory_unit)

    "~*s~*s\n"
    |> :io_lib.format([-label_width, name, @median_width, median_format])
    |> to_string
  end

  defp format_comparison(scenario, %{memory: memory_unit}, label_width, slower) do
    %Scenario{name: name, memory_usage_statistics: %Statistics{median: median}} = scenario
    median_format = Helpers.duration_output(median, memory_unit)

    "~*s~*s - ~.2fx memory usage\n"
    |> :io_lib.format([-label_width, name, @median_width, median_format, slower])
    |> to_string
  end
end
