using GreenGuest_Web.Core.Entities;
using GreenGuest_Web.DataAccess.Contexts;
using GreenGuest_Web.DataAccess.DataInitializers;
using GreenGuest_Web.DataAccess.Interceptors;
using GreenGuest_Web.DataAccess.Repositories.Abstractions;
using GreenGuest_Web.DataAccess.Repositories.Implementations;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GreenGuest_Web.DataAccess.ServiceRegistrations;

public static class DataAccesServiceRegistration
{
	public static IServiceCollection AddDataAccessServices(this IServiceCollection services, IConfiguration configuration)
	{
		services.AddDbContext<AppDbContext>(options => options.UseNpgsql(configuration.GetConnectionString("Default")));

		services.AddScoped<BaseEntityInterceptor>();
		services.AddScoped<DbContextInitializer>();

		services.AddMemoryCache();

		_addRepositories(services);
	//	_addIdentity(services);
	

		return services;
	}

	private static void _addRepositories(IServiceCollection services)
	{
		services.AddScoped<ICategoryItemRepository, CategoryItemRepository>();
		services.AddScoped<IFaqItemRepository, FaqItemRepository>();
		services.AddScoped<ISettingRepository, SettingRepository>();
		services.AddScoped<ISliderRepository, SliderRepository>();

	}



	//private static void _addIdentity(IServiceCollection services)
	//{
	//	services.AddIdentity<AppUser, IdentityRole>(options =>
	//	{
	//		options.Password.RequiredLength = 6;
	//		options.Password.RequireNonAlphanumeric = false;
	//		options.Password.RequireLowercase = false;
	//		options.Password.RequireUppercase = false;
	//		options.User.RequireUniqueEmail = true;
	//		options.SignIn.RequireConfirmedEmail = true;
	//		options.Lockout.AllowedForNewUsers = false;
	//		options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(5);
	//		options.Lockout.MaxFailedAccessAttempts = 3;

	//	}).AddEntityFrameworkStores<AppDbContext>()
	//	  .AddDefaultTokenProviders();
	//}
}
