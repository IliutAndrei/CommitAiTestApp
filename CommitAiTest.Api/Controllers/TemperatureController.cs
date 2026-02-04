using Microsoft.AspNetCore.Mvc;

namespace CommitAiTest.Api.Controllers
{

    [ApiController]
    [Route("api/[controller]")]
    public class TemperatureController : ControllerBase
    {
        [HttpGet]
        public IActionResult Get() => Ok(new { status = "Temperature - you can survive" });
    }
}
