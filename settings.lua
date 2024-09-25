data:extend{
	{
		type = "int-setting",
		name = "cip-minimum-size",
		setting_type = "startup",
		default_value = 15,
		minimum_value = 1,
    order = "startup-a"
  },
	{
		type = "int-setting",
		name = "cip-parts-required",
		setting_type = "startup",
		default_value = 5,
		minimum_value = 1,
		order = "startup-b"
	}
}