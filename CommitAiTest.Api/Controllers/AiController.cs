using Microsoft.AspNetCore.Mvc;

namespace CommitAiTest.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AiController : ControllerBase
    {
        [HttpGet]
        public IActionResult Get() => Ok(new { status = "ollama is running just fine!" });

        [HttpGet]
        public IActionResult GetVersion() => Ok(new { status = "ollama version is 0.15.4" });
    }
}
