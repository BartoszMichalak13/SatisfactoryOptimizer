import Pkg
Pkg.add(["HTTP", "Gumbo", "Cascadia", "DataFrames", "CSV"])

using HTTP, Gumbo, Cascadia, DataFrames, CSV  

function parse_items(cell_text)
  # We look for: Amount x Text Number / min
  items = []
  # (\d+(?:\.\d+)?)   -> catches amount eg. "3" or "11.25"
  # \s*[x×]\s*        -> catches "x" or "×" with optional spaces around
  # (.*?)             -> catches name (shortest match)
  # (\d+(?:\.\d+)?)   -> catches rate / min, which is glued to the name
  # \s*/\s*min        -> ending "/ min"
  pattern = r"(\d+(?:\.\d+)?)\s*[x×]\s*(.*?)(\d+(?:\.\d+)?)\s*/\s*min"

  for match in eachmatch(pattern, cell_text)
    name = strip(match.captures[2])
    rate = parse(Float64, match.captures[3])
    push!(items, (name=name, rate=rate))
  end
  return items
end

function scrape_recipes(url = "https://satisfactory.wiki.gg/wiki/Recipes", save_to_csv=true)
  # Data source
  # url = "https://satisfactory.wiki.gg/wiki/Hard_Drive"
  # url = "https://satisfactory.wiki.gg/wiki/Recipes"
  response = HTTP.get(url)
  html_body = parsehtml(String(response.body))

  tables = eachmatch(Selector("table.wikitable"), html_body.root)
  target_table = nothing
    for t in tables
        if occursin("Ingredients", nodeText(t))
            target_table = t
            break
        end
    end
  if target_table === nothing
    println("Table not found on the page.")
    return
  end
  rows = eachmatch(Selector("tr"), target_table)

  cleaned_rows = []
  for row in rows[2:end]  # Skip header
    cells = eachmatch(Selector("td"), row)
    if length(cells) > 3  # We expect at least 4 cells: Recipe, Ingredients, Building, Products
      # Recipe name and building
      recipe_name = strip(nodeText(cells[1]))
      building = strip(replace(nodeText(cells[3]), r"\d+.*" => ""))

      # Inputs and outputs
      inputs = parse_items(nodeText(cells[2]))
      outputs = parse_items(nodeText(cells[4]))

      # Dict for this row
      row_dict = Dict{Symbol, Any}()
      row_dict[:Recipe] = recipe_name
      row_dict[:Building] = building

      # --- SANITY CHECK: INPUTS ---
      if length(inputs) > 4
        println("War: $(length(inputs)) inputs - wth?! (Recipe: $recipe_name)")
      end
      # Max 4 inputs
      for i in 1:4
        if i <= length(inputs)
          row_dict[Symbol("In$(i)_Name")] = inputs[i].name
          row_dict[Symbol("In$(i)_Rate")] = inputs[i].rate
        else
          # Fill missing for unused input slots
          row_dict[Symbol("In$(i)_Name")] = missing
          row_dict[Symbol("In$(i)_Rate")] = missing
        end
      end

      # --- SANITY CHECK: OUTPUTS ---
      if length(outputs) > 2
          println("War: $(length(outputs)) outputs - wth?! (Recipe: $recipe_name)")
      end
      # Max 2 outputs
      for i in 1:2
        if i <= length(outputs)
          row_dict[Symbol("Out$(i)_Name")] = outputs[i].name
          row_dict[Symbol("Out$(i)_Rate")] = outputs[i].rate
        else
          # Fill missing for unused output slots
          row_dict[Symbol("Out$(i)_Name")] = missing
          row_dict[Symbol("Out$(i)_Rate")] = missing
        end
      end

      push!(cleaned_rows, row_dict)
    end
  end


  cols_order = [:Recipe, :Building,
                :In1_Name, :In1_Rate, :In2_Name, :In2_Rate,
                :In3_Name, :In3_Rate, :In4_Name, :In4_Rate,
                :Out1_Name, :Out1_Rate, :Out2_Name, :Out2_Rate]
  # Save to df (and CSV)
  if isempty(cleaned_rows)
    println("No data found in the table.")
    return
  else
    df = DataFrame(cleaned_rows)
    select!(df, cols_order)
    if save_to_csv
      CSV.write("all_recipes.csv", df)
    end
    println("Saved to: all_recipes.csv")
  end
  return df
end

function scrape_awesome_sink()
  url = "https://satisfactory.wiki.gg/wiki/AWESOME_Sink"

  try
    response = HTTP.get(url)
    html = parsehtml(String(response.body))
    tables = eachmatch(Selector("table.wikitable"), html.root)
    target_table = nothing

    for t in tables
      header_text = nodeText(t)
      if occursin("Points", header_text) && occursin("Items", header_text)
        target_table = t
        break
      end
    end

    if target_table === nothing
      println("Table with sink points not found on the page.")
      return
    end

    rows = eachmatch(Selector("tr"), target_table)
    data = []

    for row in rows[2:end]
      cells = eachmatch(Selector("td"), row)

      # Points are in the first cell, items in the second
      if length(cells) >= 2
        points_raw = strip(nodeText(cells[1]))
        points_clean = replace(points_raw, "," => "")

        points = tryparse(Int, points_clean)

        if points !== nothing
          items_links = eachmatch(Selector("a"), cells[2])

          for link in items_links
            item_name = strip(nodeText(link))
            if !isempty(item_name)
              push!(data, (Item=item_name, Points=points))
            end
          end
        end
      end
    end

    if !isempty(data)
      df = DataFrame(data)
      # Sort by points descending, then by item name ascending
      sort!(df, :Points)

      filename = "sink_points.csv"
      CSV.write(filename, df)

      println("   Found $(nrow(df)) items.")
      println("   Saved in: $filename")

      println("\n   Head (Top 3):")
      println(first(df, 3))
    else
      println("Table found but no valid data extracted.")
    end

  catch e
    if isa(e, HTTP.ExceptionRequest.StatusError) && e.status == 403
      println("Error 403: Access forbidden. The wiki might be blocking our requests due to too many attempts.")
    else
      println("Error: $e")
    end
  end
end

# scrape_awesome_sink()
# df = scrape_recipes()
