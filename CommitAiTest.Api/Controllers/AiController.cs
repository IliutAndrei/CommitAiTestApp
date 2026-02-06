using Microsoft.AspNetCore.Mvc;

namespace CommitAiTest.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AiController : ControllerBase
    {
        [HttpGet]
        public IActionResult Get() => Ok(new { status = "Ollama is running just fine!" });
    }
}
