import com.amazonaws.services.glue.GlueContext
import com.amazonaws.services.glue.util.GlueArgParser
import com.amazonaws.services.glue.util.Job
import org.apache.spark.SparkContext

object GlueJobWrapper {
  def main(sysArgs: Array[String]): Unit = {
    // Just call the main class
    FinancialTransactionProcessor.main(sysArgs)
  }
}
