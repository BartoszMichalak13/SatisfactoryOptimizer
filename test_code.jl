using CSV, DataFrames

df_recipes = CSV.read("all_recipes.csv", DataFrame)
# list all building used in recipes (for potential future constraints)
building_set = Set{String}()
for row in eachrow(df_recipes)
    if !ismissing(row.Building) && row.Building != ""
        push!(building_set, row.Building)
    end
end
println("   -> Unique buildings found in recipes: ", length(building_set))
println(building_set)

# Replace missing values with empty strings/zeros to avoid errors
df_recipes = coalesce.(df_recipes, "")