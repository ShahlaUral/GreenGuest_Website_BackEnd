using GreenGuest_Web.Business.ServiceRegistrations;
using GreenGuest_Web.Core.Entities;
using GreenGuest_Web.DataAccess.Contexts;
using GreenGuest_Web.DataAccess.Interceptors;
using GreenGuest_Web.DataAccess.ServiceRegistrations;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace GreenGuest_Web
{
	public class Program
	{
		public static void Main(string[] args)
		{
			var builder = WebApplication.CreateBuilder(args);
			builder.Services.AddScoped<BaseEntityInterceptor>();

			builder.Services.AddDbContext<AppDbContext>(options =>
			options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection"))
);

			// 🔹 Identity konfiqurasiyası
			builder.Services.AddIdentity<AppUser, IdentityRole>()
				.AddEntityFrameworkStores<AppDbContext>()
				.AddDefaultTokenProviders();
			// Add services to the container.
			builder.Services.AddDataAccessServices(builder.Configuration);
			builder.Services.AddBusinessLayerServices();
			builder.Services.AddControllersWithViews();
			builder.Services.AddAuthorization();
            builder.Services.AddSession(options =>
            {
                options.IdleTimeout = TimeSpan.FromMinutes(30); // sessiyanın müddəti
                options.Cookie.HttpOnly = true;
                options.Cookie.IsEssential = true;
            });
            // 🔹 Sayt nginx arxasında işləyir, orijinal sxem və IP oradan gəlir
            builder.Services.Configure<ForwardedHeadersOptions>(options =>
            {
                options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            });
            var app = builder.Build();

			app.UseForwardedHeaders();

			// Configure the HTTP request pipeline.
			if (!app.Environment.IsDevelopment())
			{
				app.UseExceptionHandler("/Home/Error");
				// The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
				app.UseHsts();
			}
			
			
			
			app.UseHttpsRedirection();
			app.UseStaticFiles();

            app.UseSession();
            app.UseRouting();
			app.UseAuthentication();
			app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
				endpoints.MapControllerRoute(
				  name: "areas",
				  pattern: "{area:exists}/{controller=Dashboard}/{action=Index}/{id?}");
                
                endpoints.MapControllerRoute(
               "default",
                "{controller=Home}/{action=Index}/{id?}");
            });
           

			app.Run();
		}
	}
}
