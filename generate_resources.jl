using DataFrames, CSV

function create_resource_limits()
    data = [
        ("Iron Ore",        92100.0),
        ("Limestone",       69300.0),
        ("Coal",            42300.0),
        ("Copper Ore",      36900.0),
        ("Caterium Ore",    15000.0),
        ("Raw Quartz",      13500.0),
        # ("Water",           13125.0), # Just from wells
        ("Water",           99999999999.0), 
        ("Crude Oil",       12600.0),
        ("Bauxite",         12300.0),
        ("Nitrogen Gas",    12000.0),
        ("Sulfur",          10800.0),
        ("SAM",             10200.0),
        ("Uranium",         2100.0)
    ]

    df = DataFrame(Resource = [x[1] for x in data], Max_Rate_Min = [x[2] for x in data])

    filename = "global_resources.csv"
    CSV.write(filename, df)
    
    println(df)
end

create_resource_limits()